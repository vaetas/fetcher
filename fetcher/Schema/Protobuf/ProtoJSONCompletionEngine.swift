import Foundation

struct ProtoJSONCompletionEngine: Sendable {
    func completions(
        json: String,
        cursorUTF16Offset: Int,
        messageType: ProtobufTypeID,
        registry: ProtobufRegistry,
        prefix: String = ""
    ) -> [CompletionItem] {
        guard let descriptor = registry.snapshot.messagesByName[messageType.fullName] else {
            return []
        }

        let effectivePrefix = prefix.isEmpty
            ? inferredPrefix(json: json, cursorUTF16Offset: cursorUTF16Offset)
            : prefix

        let presentKeys = parsedObjectKeys(in: json, cursorUTF16Offset: cursorUTF16Offset)
        let missingFields = descriptor.fields.filter { !presentKeys.contains($0.jsonName) }

        let items = missingFields.map { field in
            CompletionItem(
                label: field.jsonName,
                detail: fieldTypeDetail(field),
                documentation: field.documentation,
                insertText: "\"\(field.jsonName)\": \(sampleValue(for: field, registry: registry))",
                kind: .field,
                deprecated: field.isDeprecated
            )
        }

        return rank(items: items, prefix: effectivePrefix)
    }

    private func fieldTypeDetail(_ field: ProtoFieldDescriptor) -> String {
        switch field.cardinality {
        case .repeated: "[\(field.typeName)]"
        case .map: field.typeName
        case .optional: field.typeName
        case .required: "\(field.typeName) (required)"
        }
    }

    private func sampleValue(for field: ProtoFieldDescriptor, registry: ProtobufRegistry) -> String {
        switch field.cardinality {
        case .repeated: return "[]"
        case .map: return "{}"
        case .optional, .required:
            if registry.snapshot.messagesByName[field.typeName] != nil {
                return "{}"
            }
            if registry.snapshot.enumsByName[field.typeName] != nil {
                let first = registry.snapshot.enumsByName[field.typeName]?.values.first?.name ?? "VALUE"
                return "\"\(first)\""
            }
            switch field.typeName {
            case "string": return "\"\""
            case "bool": return "false"
            case "bytes": return "\"\""
            case "double", "float": return "0"
            case "int32", "int64", "uint32", "uint64", "sint32", "sint64", "fixed32", "fixed64", "sfixed32", "sfixed64":
                return "0"
            default: return "null"
            }
        }
    }

    private func parsedObjectKeys(in json: String, cursorUTF16Offset: Int) -> Set<String> {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        return Set(object.keys)
    }

    private func inferredPrefix(json: String, cursorUTF16Offset: Int) -> String {
        guard cursorUTF16Offset > 0, cursorUTF16Offset <= json.utf16.count else { return "" }
        let utf16Index = json.utf16.index(json.utf16.startIndex, offsetBy: cursorUTF16Offset)
        guard let stringIndex = utf16Index.samePosition(in: json) else { return "" }
        let prefix = String(json[..<stringIndex])

        if let quoteStart = prefix.range(of: "\"", options: .backwards) {
            let afterQuote = prefix[quoteStart.upperBound...]
            if !afterQuote.contains("\"") {
                return String(afterQuote)
            }
        }

        guard let last = prefix.last, last.isLetter || last == "_" else { return "" }
        var token = ""
        for scalar in prefix.reversed() {
            if scalar.isLetter || scalar == "_" || scalar == "$" {
                token.insert(scalar, at: token.startIndex)
            } else {
                break
            }
        }
        return token
    }

    private func rank(items: [CompletionItem], prefix: String) -> [CompletionItem] {
        guard !prefix.isEmpty else {
            return items.sorted { lhs, rhs in
                if lhs.deprecated != rhs.deprecated { return !lhs.deprecated }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
        }

        let lowerPrefix = prefix.lowercased()
        return items.sorted { lhs, rhs in
            let lhsRank = rankScore(for: lhs.label, prefix: prefix, lowerPrefix: lowerPrefix)
            let rhsRank = rankScore(for: rhs.label, prefix: prefix, lowerPrefix: lowerPrefix)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.deprecated != rhs.deprecated { return !lhs.deprecated }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    private func rankScore(for label: String, prefix: String, lowerPrefix: String) -> Int {
        if label.hasPrefix(prefix) { return 0 }
        if label.lowercased().hasPrefix(lowerPrefix) { return 1 }
        return 2
    }
}
