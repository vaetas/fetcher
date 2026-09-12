import AppKit
import Foundation

enum EditorSearchHighlighter {
    static func ranges(
        of query: String,
        in text: String,
        maxScanLength: Int = ResponseBodyLimits.maxSearchScanCharacters
    ) -> [NSRange] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let scanLength = min((text as NSString).length, maxScanLength)
        guard scanLength > 0 else { return [] }

        let nsText = text as NSString
        let scanRange = NSRange(location: 0, length: scanLength)
        var matches: [NSRange] = []
        var searchRange = scanRange

        while searchRange.location < scanRange.upperBound {
            let found = nsText.range(of: trimmed, options: [.caseInsensitive], range: searchRange)
            if found.location == NSNotFound { break }
            matches.append(found)
            searchRange.location = found.location + found.length
            searchRange.length = scanRange.upperBound - searchRange.location
        }

        return matches
    }

    static func apply(
        to attributed: NSMutableAttributedString,
        query: String,
        activeMatchIndex: Int
    ) -> [NSRange] {
        let matches = ranges(of: query, in: attributed.string)
        guard !matches.isEmpty else { return [] }

        let matchHighlight = NSColor.findHighlightColor
        let activeHighlight = NSColor.systemOrange.withAlphaComponent(0.55)

        for (index, range) in matches.enumerated() {
            let color = index == activeMatchIndex ? activeHighlight : matchHighlight
            attributed.addAttribute(.backgroundColor, value: color, range: range)
        }

        return matches
    }
}
