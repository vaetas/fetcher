import Foundation

struct GraphQLCompletionEngine: Sendable {
    private let languageService: any GraphQLLanguageService

    init(languageService: any GraphQLLanguageService = BuiltinGraphQLLanguageService()) {
        self.languageService = languageService
    }

    func completions(
        document: String,
        cursorUTF16Offset: Int,
        schema: GraphQLSchemaSnapshot,
        prefix: String = ""
    ) -> [CompletionItem] {
        let raw = languageService.completions(
            document: document,
            cursorUTF16Offset: cursorUTF16Offset,
            schema: schema
        )
        return rank(items: raw, prefix: prefix.isEmpty ? inferredPrefix(document: document, cursorUTF16Offset: cursorUTF16Offset) : prefix)
    }

    private func inferredPrefix(document: String, cursorUTF16Offset: Int) -> String {
        guard cursorUTF16Offset > 0, cursorUTF16Offset <= document.utf16.count else { return "" }
        let utf16Index = document.utf16.index(document.utf16.startIndex, offsetBy: cursorUTF16Offset)
        guard let stringIndex = utf16Index.samePosition(in: document) else { return "" }
        let prefix = String(document[..<stringIndex])
        guard let last = prefix.last, last.isLetter || last == "_" else { return "" }
        var token = ""
        for scalar in prefix.reversed() {
            if scalar.isLetter || scalar == "_" {
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
        if fuzzyMatches(label: label.lowercased(), pattern: lowerPrefix) { return 2 }
        return 3
    }

    private func fuzzyMatches(label: String, pattern: String) -> Bool {
        guard !pattern.isEmpty else { return true }
        var labelIndex = label.startIndex
        for character in pattern {
            guard let found = label[labelIndex...].firstIndex(of: character) else { return false }
            labelIndex = label.index(after: found)
        }
        return true
    }
}
