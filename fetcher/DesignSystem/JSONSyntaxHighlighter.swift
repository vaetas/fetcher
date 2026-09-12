import AppKit
import Foundation

enum JSONSyntaxHighlighter {
    static func isValidJSON(_ text: String) -> Bool {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

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

            if character == "\"" {
                let start = index
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

                let range = text.utf16Range(from: start, to: index)
                let isKey = nextNonWhitespaceCharacter(in: text, after: index) == ":"
                let color = isKey ? NSColor.systemTeal : NSColor.systemRed
                result.addAttribute(.foregroundColor, value: color, range: range)
            } else if character == "-" || character.isNumber {
                let start = index
                index = text.index(after: index)
                while index < text.endIndex, isNumberCharacter(text[index]) {
                    index = text.index(after: index)
                }
                let range = text.utf16Range(from: start, to: index)
                result.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
            } else if character == "t", text[index...].hasPrefix("true") {
                let end = text.index(index, offsetBy: 4, limitedBy: text.endIndex) ?? text.endIndex
                let range = text.utf16Range(from: index, to: end)
                result.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: range)
                index = end
            } else if character == "f", text[index...].hasPrefix("false") {
                let end = text.index(index, offsetBy: 5, limitedBy: text.endIndex) ?? text.endIndex
                let range = text.utf16Range(from: index, to: end)
                result.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: range)
                index = end
            } else if character == "n", text[index...].hasPrefix("null") {
                let end = text.index(index, offsetBy: 4, limitedBy: text.endIndex) ?? text.endIndex
                let range = text.utf16Range(from: index, to: end)
                result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                index = end
            } else if "{}[],:".contains(character) {
                let end = text.index(after: index)
                let range = text.utf16Range(from: index, to: end)
                result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                index = end
            } else {
                index = text.index(after: index)
            }
        }

        return result
    }

    private static func nextNonWhitespaceCharacter(in text: String, after index: String.Index) -> Character? {
        var cursor = index
        while cursor < text.endIndex {
            let character = text[cursor]
            if !character.isWhitespace {
                return character
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func isNumberCharacter(_ character: Character) -> Bool {
        character.isNumber || character == "." || character == "e" || character == "E" || character == "+" || character == "-"
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
