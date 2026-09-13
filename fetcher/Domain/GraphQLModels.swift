import Foundation

enum GraphQLHTTPMethodPreference: String, Codable, Sendable, CaseIterable {
    case post
    case getForQueries

    var displayName: String {
        switch self {
        case .post: "POST"
        case .getForQueries: "GET (queries only)"
        }
    }
}

struct GraphQLRequestDraft: Sendable {
    var requestID: UUID
    var projectID: UUID
    var name: String
    var definitionSourceID: DefinitionSourceID?
    var endpoint: String
    var document: String
    var operationName: String?
    var variablesJSON: String
    var extensionsJSON: String?
    var methodPreference: GraphQLHTTPMethodPreference
    var headers: [KeyValueEntry]
    var authKind: AuthKind
    var bearerToken: String?
    var bearerPrefix: String
    var basicUsername: String?
    var basicPassword: String?
    var apiKeyName: String?
    var apiKeyValue: String?
    var apiKeyLocation: APIKeyLocation
    var timeoutSeconds: TimeInterval?
    var baseURL: String
    var variables: [String: String]
    var secretVariables: [String: String]
}

struct GraphQLErrorLocation: Sendable, Equatable, Codable {
    var line: Int
    var column: Int
}

struct GraphQLResponseError: Sendable, Equatable, Identifiable {
    let id: UUID
    var message: String
    var path: [String]
    var locations: [GraphQLErrorLocation]
    var extensionsJSON: String?

    init(
        id: UUID = UUID(),
        message: String,
        path: [String] = [],
        locations: [GraphQLErrorLocation] = [],
        extensionsJSON: String? = nil
    ) {
        self.id = id
        self.message = message
        self.path = path
        self.locations = locations
        self.extensionsJSON = extensionsJSON
    }
}

struct GraphQLResponseArtifact: Sendable, Identifiable {
    let id: UUID
    let requestID: UUID
    let startedAt: Date
    let finishedAt: Date
    let endpointURL: URL?
    let httpStatusCode: Int?
    let httpHeaders: [(String, String)]
    let rawBody: Data
    let dataJSON: String?
    let errors: [GraphQLResponseError]
    let extensionsJSON: String?
    let metrics: RequestMetrics?
    let error: GraphQLExecutionError?
}

enum GraphQLExecutionError: Error, Sendable, Equatable {
    case invalidEndpoint(String)
    case unresolvedVariable(String)
    case invalidDocument(String)
    case invalidVariables(String)
    case mutationRequiresPOST
    case transport(TransportError)
    case timeout
    case cancelled
    case responseTooLarge(Int)
    case validation([RequestValidationIssue])

    var title: String {
        switch self {
        case .invalidEndpoint: "Invalid URL"
        case .unresolvedVariable: "Unresolved variable"
        case .invalidDocument: "Invalid GraphQL document"
        case .invalidVariables: "Invalid variables"
        case .mutationRequiresPOST: "Mutation requires POST"
        case .transport: "Network error"
        case .timeout: "Request timed out"
        case .cancelled: "Cancelled"
        case .responseTooLarge: "Response too large"
        case .validation: "Validation failed"
        }
    }

    var message: String {
        switch self {
        case .invalidEndpoint(let detail),
             .unresolvedVariable(let detail),
             .invalidDocument(let detail),
             .invalidVariables(let detail):
            return detail
        case .mutationRequiresPOST:
            return "GET is only allowed for query operations."
        case .transport(let error):
            return error.message
        case .timeout:
            return "The request exceeded the configured timeout."
        case .cancelled:
            return "The request was cancelled."
        case .responseTooLarge(let bytes):
            return "Response exceeded the in-memory limit (\(bytes) bytes)."
        case .validation(let issues):
            return issues.map(\.message).joined(separator: "\n")
        }
    }
}
