import Foundation

enum SecretRedactor: Sendable {
    private static let sensitiveHeaderNames: Set<String> = [
        "authorization",
        "cookie",
        "set-cookie",
        "proxy-authorization",
        "x-api-key",
        "api-key",
    ]

    static let redactedPlaceholder = "••••••••"

    static func redactHeader(name: String, value: String) -> String {
        if isSensitiveHeader(name) {
            return redactedPlaceholder
        }
        return value
    }

    static func isSensitiveHeader(_ name: String) -> Bool {
        let lowered = name.lowercased()
        if sensitiveHeaderNames.contains(lowered) {
            return true
        }
        return lowered.contains("api-key") || lowered.contains("token") || lowered.contains("secret")
    }

    static func redactHeaders(_ headers: [(String, String)]) -> [(String, String)] {
        headers.map { name, value in
            (name, redactHeader(name: name, value: value))
        }
    }

    static func redactSecrets(in text: String, secrets: [String]) -> String {
        secrets.reduce(text) { partial, secret in
            guard !secret.isEmpty else { return partial }
            return partial.replacingOccurrences(of: secret, with: redactedPlaceholder)
        }
    }

    static func containsSecret(_ text: String, secrets: [String]) -> Bool {
        secrets.contains { !$0.isEmpty && text.contains($0) }
    }
}
