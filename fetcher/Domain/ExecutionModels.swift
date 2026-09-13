import Foundation

enum ExecutionState: Sendable, Equatable {
    case idle
    case running
    case cancelled
}

struct RequestWarning: Identifiable, Sendable, Equatable {
    let id: UUID
    let message: String

    init(id: UUID = UUID(), message: String) {
        self.id = id
        self.message = message
    }
}

struct RequestValidationIssue: Identifiable, Sendable, Equatable {
    let id: UUID
    let message: String
    let isBlocking: Bool

    init(id: UUID = UUID(), message: String, isBlocking: Bool = true) {
        self.id = id
        self.message = message
        self.isBlocking = isBlocking
    }
}

enum RedirectPolicy: String, Codable, Sendable, CaseIterable {
    case follow
    case doNotFollow

    var displayName: String {
        switch self {
        case .follow: "Follow redirects"
        case .doNotFollow: "Do not follow"
        }
    }
}

enum TLSPolicy: String, Codable, Sendable, CaseIterable {
    case systemDefault

    var displayName: String {
        "System default"
    }
}

enum CookiePolicy: String, Codable, Sendable, CaseIterable {
    case isolatedEphemeral

    var displayName: String {
        "Isolated (ephemeral)"
    }
}

enum CachePolicy: String, Codable, Sendable, CaseIterable {
    case ignoreLocalCache

    var displayName: String {
        "Ignore local cache"
    }
}

struct RequestMetrics: Sendable, Equatable {
    var totalDuration: TimeInterval?
    var dnsLookup: TimeInterval?
    var tcpConnect: TimeInterval?
    var tlsHandshake: TimeInterval?
    var requestDuration: TimeInterval?
    var timeToFirstByte: TimeInterval?
    var responseDownload: TimeInterval?
    var negotiatedProtocol: String?
    var reusedConnection: Bool?
    var redirectCount: Int
}

struct RedirectEvent: Sendable, Equatable, Identifiable {
    let id: UUID
    let statusCode: Int
    let fromURL: URL?
    let toURL: URL?

    init(id: UUID = UUID(), statusCode: Int, fromURL: URL?, toURL: URL?) {
        self.id = id
        self.statusCode = statusCode
        self.fromURL = fromURL
        self.toURL = toURL
    }
}

enum APIRequestDraft: Sendable {
    case rest(RESTRequestDraft)
    case graphql(GraphQLRequestDraft)
    case grpc(GRPCRequestDraft)

    var protocolKind: APIProtocolKind {
        switch self {
        case .rest: .rest
        case .graphql: .graphql
        case .grpc: .grpc
        }
    }

    var projectID: UUID {
        switch self {
        case .rest(let draft): draft.projectID
        case .graphql(let draft): draft.projectID
        case .grpc(let draft): draft.projectID
        }
    }

    var requestID: UUID {
        switch self {
        case .rest(let draft): draft.requestID
        case .graphql(let draft): draft.requestID
        case .grpc(let draft): draft.requestID
        }
    }
}

struct APIMessage: Sendable, Identifiable, Equatable {
    enum Kind: String, Sendable {
        case responseBody
        case graphqlData
        case grpcMessage
    }

    let id: UUID
    let kind: Kind
    let sequence: Int
    let arrivedAt: Date
    let text: String
    let rawData: Data?

    init(
        id: UUID = UUID(),
        kind: Kind,
        sequence: Int = 0,
        arrivedAt: Date = .now,
        text: String,
        rawData: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.sequence = sequence
        self.arrivedAt = arrivedAt
        self.text = text
        self.rawData = rawData
    }
}

struct APICompletion: Sendable, Equatable {
    let finishedAt: Date
    let summary: String?
}

enum APIExecutionFailure: Error, Sendable, Equatable {
    case rest(RESTExecutionError)
    case graphql(GraphQLExecutionError)
    case grpc(GRPCExecutionError)
    case unsupportedProtocol(APIProtocolKind)
    case cancelled

    var title: String {
        switch self {
        case .rest(let error): error.title
        case .graphql(let error): error.title
        case .grpc(let error): error.title
        case .unsupportedProtocol(let kind): "Unsupported protocol"
        case .cancelled: "Cancelled"
        }
    }

    var message: String {
        switch self {
        case .rest(let error): error.message
        case .graphql(let error): error.message
        case .grpc(let error): error.message
        case .unsupportedProtocol(let kind): "No executor is registered for \(kind.displayName)."
        case .cancelled: "The request was cancelled."
        }
    }
}

enum APIExecutionEvent: Sendable {
    case started(Date)
    case requestMetadata([(String, String)])
    case responseMetadata([(String, String)])
    case message(APIMessage)
    case completed(APICompletion)
    case failed(APIExecutionFailure)
}

enum APIExecutionResult: Sendable {
    case rest(RESTResponseArtifact)
    case graphql(GraphQLResponseArtifact)
    case grpc(GRPCResponseArtifact)
}

struct ExecutionContext: Sendable {
    let projectID: UUID
    let environmentID: UUID?
}
