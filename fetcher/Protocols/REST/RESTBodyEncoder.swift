import Foundation

enum RESTBodyEncoder {
    static func encode(mode: RESTBodyMode, text: String) throws -> (data: Data?, contentType: String?, warnings: [RequestWarning]) {
        switch mode {
        case .none:
            return (nil, nil, [])
        case .json:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return (Data(), "application/json", [RequestWarning(message: "JSON body is empty.")])
            }
            guard let data = text.data(using: .utf8) else {
                throw RESTExecutionError.invalidJSON("JSON body is not valid UTF-8.")
            }
            do {
                _ = try JSONSerialization.jsonObject(with: data)
            } catch {
                throw RESTExecutionError.invalidJSON(error.localizedDescription)
            }
            return (data, "application/json", [])
        case .text:
            guard let data = text.data(using: .utf8) else {
                throw RESTExecutionError.unsupportedResponseEncoding
            }
            return (data, "text/plain; charset=utf-8", [])
        }
    }

    static func formatJSON(_ text: String) throws -> String {
        guard let data = text.data(using: .utf8) else {
            throw RESTExecutionError.invalidJSON("JSON body is not valid UTF-8.")
        }
        let object = try JSONSerialization.jsonObject(with: data)
        let pretty = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let string = String(data: pretty, encoding: .utf8) else {
            throw RESTExecutionError.invalidJSON("Unable to encode formatted JSON.")
        }
        return string
    }
}
