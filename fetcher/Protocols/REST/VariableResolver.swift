import Foundation

struct VariableScope: Sendable {
    var values: [String: String]

    init(values: [String: String] = [:]) {
        self.values = values
    }
}

struct ResolvedString: Sendable, Equatable {
    let value: String
    let unresolvedNames: [String]
    let warnings: [RequestWarning]
}

protocol VariableResolving: Sendable {
    func resolve(_ input: String, scope: VariableScope) throws -> ResolvedString
}

struct VariableResolver: VariableResolving, Sendable {
    private let maxDepth: Int

    init(maxDepth: Int = 8) {
        self.maxDepth = maxDepth
    }

    func resolve(_ input: String, scope: VariableScope) throws -> ResolvedString {
        var unresolved: [String] = []
        var warnings: [RequestWarning] = []
        let pattern = /\{\{\s*([A-Za-z0-9_.-]+)\s*\}\}/
        var result = input
        var depth = 0
        var seenFrames: [[String: String]] = []

        while result.contains("{{"), depth < maxDepth {
            depth += 1
            var next = result
            var replacedAny = false
            let matches = Array(result.matches(of: pattern))
            guard !matches.isEmpty else { break }

            var frame: [String: String] = [:]
            for match in matches.reversed() {
                let name = String(match.1)
                guard let value = scope.values[name] else {
                    if !unresolved.contains(name) {
                        unresolved.append(name)
                        warnings.append(RequestWarning(message: "Unresolved variable: {{\(name)}}"))
                    }
                    continue
                }
                frame[name] = value
                next.replaceSubrange(match.range, with: value)
                replacedAny = true
            }

            if seenFrames.contains(where: { $0 == frame }), replacedAny {
                if let cyclic = frame.keys.sorted().first {
                    throw VariableResolutionError.circularReference(cyclic)
                }
            }
            seenFrames.append(frame)

            if !replacedAny {
                break
            }
            if next == result {
                break
            }
            result = next
        }

        if depth >= maxDepth, result.contains("{{") {
            throw VariableResolutionError.recursionLimitExceeded
        }

        return ResolvedString(value: result, unresolvedNames: unresolved, warnings: warnings)
    }
}

enum VariableResolutionError: Error, Sendable, Equatable {
    case circularReference(String)
    case recursionLimitExceeded
}
