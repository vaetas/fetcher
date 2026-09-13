import AppKit
import Foundation

enum CodeEditorContentRenderer {
    static func plainAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: NSColor.labelColor]
    }

    static func shouldSyntaxHighlight(text: String, isJSON: Bool, syntaxMode: CodeEditorSyntaxMode, isEditable: Bool) -> Bool {
        guard text.count <= ResponseBodyLimits.maxSyntaxHighlightCharacters else { return false }
        switch syntaxMode {
        case .jsonWhenValid:
            return !isEditable && isJSON
        case .graphql:
            return false
        case .plain:
            return false
        }
    }

    static func shouldDeferGraphQLSyntaxHighlight(text: String, syntaxMode: CodeEditorSyntaxMode) -> Bool {
        syntaxMode == .graphql && text.count <= ResponseBodyLimits.maxSyntaxHighlightCharacters
    }

    static func buildAttributedString(
        text: String,
        font: NSFont,
        syntaxMode: CodeEditorSyntaxMode = .plain,
        shouldHighlightJSON: Bool,
        searchQuery: String,
        activeSearchMatchIndex: Int
    ) -> (NSAttributedString, [NSRange]) {
        let attributed: NSMutableAttributedString
        if syntaxMode == .graphql {
            attributed = NSMutableAttributedString(
                attributedString: GraphQLSyntaxHighlighter.attributedString(for: text, font: font)
            )
        } else if shouldHighlightJSON {
            attributed = NSMutableAttributedString(
                attributedString: JSONSyntaxHighlighter.attributedString(for: text, font: font)
            )
        } else {
            attributed = NSMutableAttributedString(string: text)
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            attributed.addAttributes(plainAttributes(font: font), range: fullRange)
        }

        let matches = EditorSearchHighlighter.apply(
            to: attributed,
            query: searchQuery,
            activeMatchIndex: activeSearchMatchIndex
        )
        return (attributed, matches)
    }
}
