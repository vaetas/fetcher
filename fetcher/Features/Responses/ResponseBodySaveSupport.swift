import AppKit
import Foundation
import UniformTypeIdentifiers

struct ResponseBodySaveDescriptor: Equatable {
    let fileExtension: String
    let allowedContentTypes: [UTType]
}

enum ResponseBodySaveSupport {
    static func isSaveable(_ response: RESTResponseArtifact) -> Bool {
        guard response.error == nil else { return false }
        guard let statusCode = response.statusCode, (200..<300).contains(statusCode) else { return false }
        return !response.body.isEmpty
    }

    static func isSaveable(_ response: GraphQLResponseArtifact) -> Bool {
        guard response.error == nil else { return false }
        guard !response.rawBody.isEmpty else { return false }
        if let statusCode = response.httpStatusCode {
            return (200..<300).contains(statusCode)
        }
        return true
    }

    static func isSaveable(_ artifact: GRPCResponseArtifact, message: GRPCMessageEvent?) -> Bool {
        guard artifact.error == nil else { return false }
        guard let message else { return false }
        return !message.json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func descriptor(for response: RESTResponseArtifact, bodyIsJSON: Bool) -> ResponseBodySaveDescriptor {
        ResponseBodySaveDescriptor(
            fileExtension: fileExtension(mimeType: response.mimeType, bodyIsJSON: bodyIsJSON),
            allowedContentTypes: allowedContentTypes(mimeType: response.mimeType, bodyIsJSON: bodyIsJSON)
        )
    }

    static func descriptor(for response: GraphQLResponseArtifact) -> ResponseBodySaveDescriptor {
        jsonDescriptor()
    }

    static func descriptor(for message: GRPCMessageEvent) -> ResponseBodySaveDescriptor {
        jsonDescriptor()
    }

    static func save(data: Data, requestName: String, descriptor: ResponseBodySaveDescriptor) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = descriptor.allowedContentTypes
        panel.nameFieldStringValue = defaultFilename(
            requestName: requestName,
            fileExtension: descriptor.fileExtension
        )
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    static func defaultFilename(
        requestName: String,
        fileExtension: String,
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) -> String {
        let base = sanitizedRequestName(requestName)
        let ext = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !ext.isEmpty else { return "\(base)-\(timestamp)" }
        return "\(base)-\(timestamp).\(ext)"
    }

    static func sanitizedRequestName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "response" }

        let slug = trimmed
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber {
                    return character
                }
                if character == "-" || character == "_" {
                    return character
                }
                if character.isWhitespace {
                    return "-"
                }
                return "-"
            }

        var collapsed = String(slug)
        while collapsed.contains("--") {
            collapsed = collapsed.replacingOccurrences(of: "--", with: "-")
        }

        collapsed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return collapsed.isEmpty ? "response" : collapsed
    }

    static func fileExtension(mimeType: String?, bodyIsJSON: Bool) -> String {
        if bodyIsJSON || mimeType?.contains("json") == true {
            return "json"
        }

        if let mimeType, let type = UTType(mimeType: mimeType),
           let ext = type.preferredFilenameExtension {
            return ext
        }

        if let mimeType, mimeType.hasPrefix("text/") {
            let subtype = mimeType.split(separator: ";", maxSplits: 1).first?
                .split(separator: "/", maxSplits: 1)
                .last
                .map(String.init)

            if let subtype, subtype != "plain", !subtype.contains("+"), subtype.allSatisfy({ $0.isLetter || $0.isNumber }) {
                return subtype
            }
            return "txt"
        }

        return "bin"
    }

    static func allowedContentTypes(mimeType: String?, bodyIsJSON: Bool) -> [UTType] {
        var types: [UTType] = []

        if let mimeType, let type = UTType(mimeType: mimeType) {
            types.append(type)
        }

        if bodyIsJSON || mimeType?.contains("json") == true {
            appendUnique(.json, to: &types)
        }

        if mimeType?.hasPrefix("text/") == true {
            appendUnique(.plainText, to: &types)
        }

        if types.isEmpty {
            types = [.data]
        }

        return types
    }

    private static func jsonDescriptor() -> ResponseBodySaveDescriptor {
        ResponseBodySaveDescriptor(
            fileExtension: "json",
            allowedContentTypes: [.json]
        )
    }

    private static func appendUnique(_ type: UTType, to types: inout [UTType]) {
        guard !types.contains(where: { $0.identifier == type.identifier }) else { return }
        types.append(type)
    }
}
