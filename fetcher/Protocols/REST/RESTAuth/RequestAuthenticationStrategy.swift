import Foundation

struct ResolvedRequestContext: Sendable {
    var url: URL
    var headers: [(String, String)]
    var queryItems: [URLQueryItem]
    var secretsUsed: [String]
}

protocol RequestAuthenticationStrategy: Sendable {
    var kind: AuthKind { get }
    func apply(
        to request: inout URLRequest,
        resolvedContext: inout ResolvedRequestContext
    ) async throws
}

struct NoneAuthStrategy: RequestAuthenticationStrategy {
    let kind: AuthKind = .none

    func apply(to request: inout URLRequest, resolvedContext: inout ResolvedRequestContext) async throws {}
}

struct BearerAuthStrategy: RequestAuthenticationStrategy {
    let kind: AuthKind = .bearer
    let token: String
    let prefix: String

    func apply(to request: inout URLRequest, resolvedContext: inout ResolvedRequestContext) async throws {
        guard !token.isEmpty else {
            throw RESTExecutionError.authenticationConfiguration("Bearer token is missing.")
        }
        let value = prefix.isEmpty ? token : "\(prefix) \(token)"
        request.setValue(value, forHTTPHeaderField: "Authorization")
        resolvedContext.headers.removeAll { $0.0.caseInsensitiveCompare("Authorization") == .orderedSame }
        resolvedContext.headers.append(("Authorization", value))
        resolvedContext.secretsUsed.append(token)
    }
}

struct BasicAuthStrategy: RequestAuthenticationStrategy {
    let kind: AuthKind = .basic
    let username: String
    let password: String

    func apply(to request: inout URLRequest, resolvedContext: inout ResolvedRequestContext) async throws {
        let credentials = "\(username):\(password)"
        guard let data = credentials.data(using: .utf8) else {
            throw RESTExecutionError.authenticationConfiguration("Unable to encode Basic credentials.")
        }
        let value = "Basic \(data.base64EncodedString())"
        request.setValue(value, forHTTPHeaderField: "Authorization")
        resolvedContext.headers.removeAll { $0.0.caseInsensitiveCompare("Authorization") == .orderedSame }
        resolvedContext.headers.append(("Authorization", value))
        if !password.isEmpty {
            resolvedContext.secretsUsed.append(password)
        }
    }
}

struct APIKeyAuthStrategy: RequestAuthenticationStrategy {
    let kind: AuthKind = .apiKey
    let name: String
    let value: String
    let location: APIKeyLocation

    func apply(to request: inout URLRequest, resolvedContext: inout ResolvedRequestContext) async throws {
        guard !name.isEmpty else {
            throw RESTExecutionError.authenticationConfiguration("API key name is missing.")
        }
        guard !value.isEmpty else {
            throw RESTExecutionError.authenticationConfiguration("API key value is missing.")
        }

        switch location {
        case .header:
            request.setValue(value, forHTTPHeaderField: name)
            resolvedContext.headers.removeAll { $0.0.caseInsensitiveCompare(name) == .orderedSame }
            resolvedContext.headers.append((name, value))
        case .query:
            guard var components = URLComponents(url: resolvedContext.url, resolvingAgainstBaseURL: false) else {
                throw RESTExecutionError.invalidEndpoint("Unable to apply API key query parameter.")
            }
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: name, value: value))
            components.queryItems = items
            guard let url = components.url else {
                throw RESTExecutionError.invalidEndpoint("Unable to build URL with API key.")
            }
            request.url = url
            resolvedContext.url = url
            resolvedContext.queryItems = items
        }
        resolvedContext.secretsUsed.append(value)
    }
}

enum AuthStrategyFactory {
    static func strategy(for draft: RESTRequestDraft, effectiveKind: AuthKind) -> any RequestAuthenticationStrategy {
        switch effectiveKind {
        case .none:
            return NoneAuthStrategy()
        case .inherit:
            return strategy(for: draft, effectiveKind: draft.projectAuthKind == .inherit ? .none : draft.projectAuthKind)
        case .bearer:
            let token = draft.authKind == .inherit ? (draft.projectBearerToken ?? "") : (draft.bearerToken ?? "")
            let prefix = draft.authKind == .inherit ? draft.projectBearerPrefix : draft.bearerPrefix
            return BearerAuthStrategy(token: token, prefix: prefix.isEmpty ? "Bearer" : prefix)
        case .basic:
            let username = draft.authKind == .inherit ? (draft.projectBasicUsername ?? "") : (draft.basicUsername ?? "")
            let password = draft.authKind == .inherit ? (draft.projectBasicPassword ?? "") : (draft.basicPassword ?? "")
            return BasicAuthStrategy(username: username, password: password)
        case .apiKey:
            let name = draft.authKind == .inherit ? (draft.projectAPIKeyName ?? "") : (draft.apiKeyName ?? "")
            let value = draft.authKind == .inherit ? (draft.projectAPIKeyValue ?? "") : (draft.apiKeyValue ?? "")
            let location = draft.authKind == .inherit ? draft.projectAPIKeyLocation : draft.apiKeyLocation
            return APIKeyAuthStrategy(name: name, value: value, location: location)
        }
    }
}
