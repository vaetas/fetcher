import Foundation

enum ResponseBodyLimits {
    static let previewByteCount = 96 * 1024
    static let maxPrettyPrintByteCount = 512 * 1024
    static let progressiveCharacterChunk = 48_000
    static let maxSyntaxHighlightCharacters = 80_000
    static let maxSearchScanCharacters = 500_000
}

struct ResponseBodyFormatResult: Sendable, Equatable {
    let text: String
    let isJSON: Bool
    let skippedPrettyPrint: Bool
    let notice: String?

    static let empty = ResponseBodyFormatResult(text: "", isJSON: false, skippedPrettyPrint: false, notice: nil)
}

enum ResponseBodyUpdate: Sendable, Equatable {
    case replace(text: String, isJSON: Bool, isComplete: Bool, notice: String?)
    case append(text: String, isComplete: Bool, notice: String?)
}

enum ResponseBodyFormatter {
    static func format(data: Data, mimeType: String?) -> String {
        formatForDisplay(data: data, mimeType: mimeType).text
    }

    static func formatForDisplay(data: Data, mimeType: String?) -> ResponseBodyFormatResult {
        if data.isEmpty { return .empty }

        if isBinary(data: data, mimeType: mimeType) {
            return ResponseBodyFormatResult(
                text: binarySummary(byteCount: data.count),
                isJSON: false,
                skippedPrettyPrint: false,
                notice: nil
            )
        }

        let likelyJSON = mimeType?.contains("json") == true || looksLikeJSON(data)
        let shouldPrettyPrint = likelyJSON && data.count <= ResponseBodyLimits.maxPrettyPrintByteCount

        if shouldPrettyPrint,
           let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return ResponseBodyFormatResult(text: text, isJSON: true, skippedPrettyPrint: false, notice: nil)
        }

        if likelyJSON, data.count > ResponseBodyLimits.maxPrettyPrintByteCount,
           let text = decodeText(data: data) {
            return ResponseBodyFormatResult(
                text: text,
                isJSON: true,
                skippedPrettyPrint: true,
                notice: "Pretty-print skipped for large JSON response."
            )
        }

        if let text = decodeText(data: data) {
            return ResponseBodyFormatResult(text: text, isJSON: likelyJSON && isValidJSON(text), skippedPrettyPrint: false, notice: nil)
        }

        return ResponseBodyFormatResult(
            text: binarySummary(byteCount: data.count),
            isJSON: false,
            skippedPrettyPrint: false,
            notice: nil
        )
    }

    static func preview(data: Data, mimeType: String?) -> ResponseBodyFormatResult? {
        guard !data.isEmpty else { return nil }
        if isBinary(data: data, mimeType: mimeType) { return nil }
        guard data.count > ResponseBodyLimits.previewByteCount else { return nil }

        let prefix = data.prefix(ResponseBodyLimits.previewByteCount)
        guard let text = decodeText(data: prefix) else { return nil }

        let likelyJSON = mimeType?.contains("json") == true || looksLikeJSON(prefix)
        let remaining = ByteCountFormatter.string(
            fromByteCount: Int64(data.count - prefix.count),
            countStyle: .file
        )
        return ResponseBodyFormatResult(
            text: text + "\n\n… Loading remaining \(remaining) …",
            isJSON: likelyJSON,
            skippedPrettyPrint: true,
            notice: nil
        )
    }

    static func loadProgressively(
        data: Data,
        mimeType: String?,
        onUpdate: @MainActor @Sendable (ResponseBodyUpdate) async -> Void
    ) async {
        if data.isEmpty {
            await onUpdate(.replace(text: "", isJSON: false, isComplete: true, notice: nil))
            return
        }

        if let preview = preview(data: data, mimeType: mimeType) {
            await onUpdate(.replace(
                text: preview.text,
                isJSON: preview.isJSON,
                isComplete: false,
                notice: preview.notice
            ))
            await Task.yield()
        }

        let result = await Task.detached(priority: .utility) {
            formatForDisplay(data: data, mimeType: mimeType)
        }.value

        guard !Task.isCancelled else { return }

        if result.text.count <= ResponseBodyLimits.progressiveCharacterChunk {
            await onUpdate(.replace(
                text: result.text,
                isJSON: result.isJSON,
                isComplete: true,
                notice: result.notice
            ))
            return
        }

        await onUpdate(.replace(
            text: "",
            isJSON: result.isJSON,
            isComplete: false,
            notice: result.notice
        ))

        var offset = result.text.startIndex
        while offset < result.text.endIndex {
            guard !Task.isCancelled else { return }

            let next = result.text.index(
                offset,
                offsetBy: ResponseBodyLimits.progressiveCharacterChunk,
                limitedBy: result.text.endIndex
            ) ?? result.text.endIndex
            let chunk = String(result.text[offset..<next])
            offset = next
            let isComplete = offset >= result.text.endIndex

            await onUpdate(.append(text: chunk, isComplete: isComplete, notice: isComplete ? result.notice : nil))
            await Task.yield()
            if !isComplete {
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
        }
    }

    static func isValidJSON(_ text: String) -> Bool {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    static func decodeText(data: Data) -> String? {
        if data.contains(0) { return nil }
        if let utf8 = String(data: data, encoding: .utf8), utf8.utf8.count == data.count {
            return utf8
        }
        return nil
    }

    static func isBinary(data: Data, mimeType: String?) -> Bool {
        if mimeType?.hasPrefix("image/") == true { return true }
        if mimeType?.hasPrefix("audio/") == true { return true }
        if mimeType?.hasPrefix("video/") == true { return true }
        if mimeType == "application/octet-stream" { return true }
        if mimeType?.contains("json") == true { return false }
        if mimeType?.hasPrefix("text/") == true { return false }
        return decodeText(data: data) == nil
    }

    private static func looksLikeJSON(_ data: Data) -> Bool {
        var index = 0
        while index < data.count {
            let byte = data[index]
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\t") {
                index += 1
                continue
            }
            return byte == UInt8(ascii: "{") || byte == UInt8(ascii: "[")
        }
        return false
    }

    private static func binarySummary(byteCount: Int) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        return "Binary response — \(size)"
    }
}
