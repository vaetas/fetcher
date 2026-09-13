import Foundation

struct CompletionItem: Sendable, Identifiable, Equatable {
    enum Kind: String, Sendable {
        case field
        case argument
        case enumCase
        case type
        case directive
        case fragment
        case service
        case method
        case keyword
        case variable
    }

    let id: String
    let label: String
    let detail: String?
    let documentation: String?
    let insertText: String
    let kind: Kind
    let deprecated: Bool

    init(
        id: String? = nil,
        label: String,
        detail: String? = nil,
        documentation: String? = nil,
        insertText: String? = nil,
        kind: Kind,
        deprecated: Bool = false
    ) {
        self.id = id ?? "\(kind.rawValue):\(label)"
        self.label = label
        self.detail = detail
        self.documentation = documentation
        self.insertText = insertText ?? label
        self.kind = kind
        self.deprecated = deprecated
    }
}

struct TextRange: Sendable, Equatable {
    var location: Int
    var length: Int

    var nsRange: NSRange {
        NSRange(location: location, length: length)
    }

    init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    init(_ range: Range<String.Index>, in string: String) {
        location = string.utf16.distance(from: string.startIndex, to: range.lowerBound)
        length = string.utf16.distance(from: range.lowerBound, to: range.upperBound)
    }
}

struct EditorDiagnostic: Sendable, Identifiable, Equatable {
    enum Severity: String, Sendable {
        case error
        case warning
        case information
    }

    let id: UUID
    let severity: Severity
    let message: String
    let range: TextRange?
    let source: String?

    init(
        id: UUID = UUID(),
        severity: Severity,
        message: String,
        range: TextRange? = nil,
        source: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.range = range
        self.source = source
    }
}
