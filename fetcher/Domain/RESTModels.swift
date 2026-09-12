import Foundation

enum RESTBodyMode: String, Codable, Sendable, CaseIterable {
    case none
    case json
    case text

    var displayName: String {
        switch self {
        case .none: "None"
        case .json: "JSON"
        case .text: "Text"
        }
    }
}

enum ParameterKind: String, Codable, Sendable, CaseIterable {
    case query
    case path
    case header
}

enum AuthKind: String, Codable, Sendable, CaseIterable {
    case none
    case inherit
    case bearer
    case basic
    case apiKey

    var displayName: String {
        switch self {
        case .none: "None"
        case .inherit: "Inherit project"
        case .bearer: "Bearer Token"
        case .basic: "Basic Auth"
        case .apiKey: "API Key"
        }
    }
}

enum APIKeyLocation: String, Codable, Sendable, CaseIterable {
    case header
    case query

    var displayName: String {
        switch self {
        case .header: "Header"
        case .query: "Query"
        }
    }
}

struct KeyValueEntry: Identifiable, Codable, Sendable, Hashable {
    var id: UUID
    var key: String
    var value: String
    var isEnabled: Bool
    var isSecret: Bool

    init(
        id: UUID = UUID(),
        key: String = "",
        value: String = "",
        isEnabled: Bool = true,
        isSecret: Bool = false
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
        self.isSecret = isSecret
    }
}

struct RESTRequestDraft: Sendable {
    var requestID: UUID
    var projectID: UUID
    var name: String
    var method: String
    var endpoint: String
    var queryParameters: [KeyValueEntry]
    var pathParameters: [KeyValueEntry]
    var headers: [KeyValueEntry]
    var bodyMode: RESTBodyMode
    var bodyText: String
    var authKind: AuthKind
    var bearerToken: String?
    var bearerPrefix: String
    var basicUsername: String?
    var basicPassword: String?
    var apiKeyName: String?
    var apiKeyValue: String?
    var apiKeyLocation: APIKeyLocation
    var timeoutSeconds: TimeInterval?
    var redirectPolicy: RedirectPolicy
    var cookiePolicy: CookiePolicy
    var cachePolicy: CachePolicy
    var tlsPolicy: TLSPolicy
    var projectDefaultHeaders: [KeyValueEntry]
    var projectAuthKind: AuthKind
    var projectBearerToken: String?
    var projectBearerPrefix: String
    var projectBasicUsername: String?
    var projectBasicPassword: String?
    var projectAPIKeyName: String?
    var projectAPIKeyValue: String?
    var projectAPIKeyLocation: APIKeyLocation
    var baseURL: String
    var variables: [String: String]
    var secretVariables: [String: String]
}

struct ResolvedRESTRequest: Sendable {
    let method: String
    let url: URL
    let headers: [(String, String)]
    let body: Data?
    let timeout: TimeInterval
    let redirectPolicy: RedirectPolicy
    let tlsPolicy: TLSPolicy
    let warnings: [RequestWarning]
}

struct PreparedRequestPreview: Sendable {
    let resolvedURL: String
    let headers: [(String, String)]
    let bodyPreview: String?
    let warnings: [RequestWarning]
}

struct RESTResponseArtifact: Sendable, Identifiable {
    let id: UUID
    let requestID: UUID
    let startedAt: Date
    let finishedAt: Date
    let originalURL: URL
    let finalURL: URL?
    let statusCode: Int?
    let headers: [(String, String)]
    let body: Data
    let mimeType: String?
    let textEncodingName: String?
    let expectedContentLength: Int64?
    let metrics: RequestMetrics?
    let redirects: [RedirectEvent]
    let error: RESTExecutionError?
}

enum RESTExecutionError: Error, Sendable, Equatable {
    case invalidEndpoint(String)
    case unresolvedVariable(String)
    case invalidJSON(String)
    case authenticationConfiguration(String)
    case transport(TransportError)
    case tls(String)
    case timeout
    case cancelled
    case responseTooLarge(Int)
    case unsupportedResponseEncoding
    case validation([RequestValidationIssue])

    var title: String {
        switch self {
        case .invalidEndpoint: "Invalid URL"
        case .unresolvedVariable: "Unresolved variable"
        case .invalidJSON: "Invalid JSON"
        case .authenticationConfiguration: "Authentication error"
        case .transport: "Network error"
        case .tls: "TLS verification failed"
        case .timeout: "Request timed out"
        case .cancelled: "Cancelled"
        case .responseTooLarge: "Response too large"
        case .unsupportedResponseEncoding: "Unsupported encoding"
        case .validation: "Validation failed"
        }
    }

    var message: String {
        switch self {
        case .invalidEndpoint(let detail): detail
        case .unresolvedVariable(let name): "The URL contains an unresolved variable: {{\(name)}}"
        case .invalidJSON(let detail): detail
        case .authenticationConfiguration(let detail): detail
        case .transport(let error): error.message
        case .tls(let detail): detail
        case .timeout: "The request exceeded the configured timeout."
        case .cancelled: "The request was cancelled."
        case .responseTooLarge(let bytes): "Response exceeded the in-memory limit (\(bytes) bytes)."
        case .unsupportedResponseEncoding: "The response encoding is not supported."
        case .validation(let issues): issues.map(\.message).joined(separator: "\n")
        }
    }
}

enum TransportError: Error, Sendable, Equatable {
    case dnsFailure(String)
    case connectionFailure(String)
    case httpError(String)
    case unknown(String)

    var message: String {
        switch self {
        case .dnsFailure(let detail),
             .connectionFailure(let detail),
             .httpError(let detail),
             .unknown(let detail):
            return detail
        }
    }
}
