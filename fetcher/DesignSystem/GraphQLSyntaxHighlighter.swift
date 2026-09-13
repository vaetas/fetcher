import AppKit
import Foundation

enum GraphQLSyntaxHighlighter {
    private static let keywords: Set<String> = [
        "query", "mutation", "subscription", "fragment", "on", "type", "interface",
        "union", "enum", "input", "scalar", "schema", "extend", "implements",
        "directive", "repeatable",
    ]

    static func attributedString(for text: String, font: NSFont) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        result.addAttributes(
            [.font: font, .foregroundColor: NSColor.labelColor],
            range: fullRange
        )

        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]

            if character == "#" {
                let start = index
                while index < text.endIndex, text[index] != "\n" {
                    index = text.index(after: index)
                }
                result.addAttribute(
                    .foregroundColor,
                    value: NSColor.secondaryLabelColor,
                    range: text.utf16Range(from: start, to: index)
                )
                continue
            }

            if character == "\"" {
                let start = index
                if text[index...].hasPrefix("\"\"\"") {
                    index = text.index(index, offsetBy: 3, limitedBy: text.endIndex) ?? text.endIndex
                    while index < text.endIndex {
                        if text[index...].hasPrefix("\"\"\"") {
                            index = text.index(index, offsetBy: 3, limitedBy: text.endIndex) ?? text.endIndex
                            break
                        }
                        index = text.index(after: index)
                    }
                } else {
                    index = text.index(after: index)
                    while index < text.endIndex {
                        if text[index] == "\\" {
                            index = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                            if index == text.endIndex { break }
                            continue
                        }
                        if text[index] == "\"" {
                            index = text.index(after: index)
                            break
                        }
                        index = text.index(after: index)
                    }
                }
                result.addAttribute(
                    .foregroundColor,
                    value: NSColor.systemOrange,
                    range: text.utf16Range(from: start, to: index)
                )
                continue
            }

            if character == "$" {
                let start = index
                index = text.index(after: index)
                while index < text.endIndex, isIdentifierCharacter(text[index]) {
                    index = text.index(after: index)
                }
                result.addAttribute(
                    .foregroundColor,
                    value: NSColor.systemPurple,
                    range: text.utf16Range(from: start, to: index)
                )
                continue
            }

            if character == "@" {
                let start = index
                index = text.index(after: index)
                while index < text.endIndex, isIdentifierCharacter(text[index]) {
                    index = text.index(after: index)
                }
                result.addAttribute(
                    .foregroundColor,
                    value: NSColor.systemTeal,
                    range: text.utf16Range(from: start, to: index)
                )
                continue
            }

            if character == "-" || character.isNumber {
                let start = index
                index = text.index(after: index)
                while index < text.endIndex, isNumberCharacter(text[index]) {
                    index = text.index(after: index)
                }
                result.addAttribute(
                    .foregroundColor,
                    value: NSColor.systemBlue,
                    range: text.utf16Range(from: start, to: index)
                )
                continue
            }

            if isIdentifierCharacter(character) {
                let start = index
                while index < text.endIndex, isIdentifierCharacter(text[index]) {
                    index = text.index(after: index)
                }
                let token = String(text[start..<index])
                if keywords.contains(token) {
                    result.addAttribute(
                        .foregroundColor,
                        value: NSColor.systemIndigo,
                        range: text.utf16Range(from: start, to: index)
                    )
                } else if token == "true" || token == "false" || token == "null" {
                    result.addAttribute(
                        .foregroundColor,
                        value: NSColor.systemPurple,
                        range: text.utf16Range(from: start, to: index)
                    )
                }
                continue
            }

            if "{}[]!:|=".contains(character) {
                let end = text.index(after: index)
                result.addAttribute(
                    .foregroundColor,
                    value: NSColor.secondaryLabelColor,
                    range: text.utf16Range(from: index, to: end)
                )
                index = end
                continue
            }

            index = text.index(after: index)
        }

        return result
    }

    private static func isIdentifierCharacter(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private static func isNumberCharacter(_ character: Character) -> Bool {
        character.isNumber || character == "." || character == "e" || character == "E" || character == "+"
    }
}

private extension String {
    func utf16Range(from start: String.Index, to end: String.Index) -> NSRange {
        let startUTF16 = start.samePosition(in: utf16)!
        let endUTF16 = end.samePosition(in: utf16)!
        let location = utf16.distance(from: utf16.startIndex, to: startUTF16)
        let length = utf16.distance(from: startUTF16, to: endUTF16)
        return NSRange(location: location, length: length)
    }
}
