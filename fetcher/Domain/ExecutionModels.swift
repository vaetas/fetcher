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

enum APIExecutionResult: Sendable {
    case rest(RESTResponseArtifact)
}

struct ExecutionContext: Sendable {
    let projectID: UUID
    let environmentID: UUID?
}
