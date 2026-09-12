import Foundation

enum RESTRequestValidator {
    static func validate(_ draft: RESTRequestDraft) -> [RequestValidationIssue] {
        var issues: [RequestValidationIssue] = []

        if draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(RequestValidationIssue(message: "Endpoint is empty.", isBlocking: true))
        }

        if draft.bodyMode == .json, !draft.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let data = draft.bodyText.data(using: .utf8) {
                do {
                    _ = try JSONSerialization.jsonObject(with: data)
                } catch {
                    issues.append(RequestValidationIssue(message: "JSON body is invalid: \(error.localizedDescription)", isBlocking: true))
                }
            } else {
                issues.append(RequestValidationIssue(message: "JSON body is not valid UTF-8.", isBlocking: true))
            }
        }

        let method = draft.method.uppercased()
        if (method == "GET" || method == "HEAD"), draft.bodyMode != .none, !draft.bodyText.isEmpty {
            issues.append(RequestValidationIssue(
                message: "\(method) requests with a body are unusual and may be rejected by intermediaries.",
                isBlocking: false
            ))
        }

        let placeholders = pathPlaceholders(in: draft.endpoint)
        let pathKeys = Set(draft.pathParameters.filter(\.isEnabled).map(\.key))
        for placeholder in placeholders where !pathKeys.contains(placeholder) {
            issues.append(RequestValidationIssue(
                message: "Missing path parameter: {\(placeholder)}",
                isBlocking: false
            ))
        }
        for entry in draft.pathParameters where entry.isEnabled && !placeholders.contains(entry.key) && !entry.key.isEmpty {
            issues.append(RequestValidationIssue(
                message: "Unused path parameter: \(entry.key)",
                isBlocking: false
            ))
        }

        return issues
    }

    static func pathPlaceholders(in endpoint: String) -> [String] {
        let pattern = /\{([A-Za-z0-9_.-]+)\}/
        return endpoint.matches(of: pattern).map { String($0.1) }
    }
}
