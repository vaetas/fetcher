import Foundation

enum GRPCCallShape: String, Codable, Sendable, CaseIterable {
    case unary
    case serverStreaming
    case clientStreaming
    case bidirectionalStreaming

    var displayName: String {
        switch self {
        case .unary: "Unary"
        case .serverStreaming: "Server streaming"
        case .clientStreaming: "Client streaming"
        case .bidirectionalStreaming: "Bidirectional"
        }
    }
}

enum GRPCStreamState: String, Sendable, Equatable {
    case idle
    case connecting
    case active
    case clientHalfClosed
    case completed
    case cancelled
    case failed
}

enum GRPCCompressionPreference: String, Codable, Sendable {
    case none
    case gzip
}

struct DurationConfiguration: Codable, Sendable, Equatable {
    var seconds: Double
}

struct GRPCRequestDraft: Sendable {
    var requestID: UUID
    var projectID: UUID
    var name: String
    var definitionSourceID: DefinitionSourceID
    var target: String
    var serviceFullName: String
    var methodName: String
    var metadata: [KeyValueEntry]
    var bodyJSON: String
    var outboundMessagesJSON: [String]
    var deadline: DurationConfiguration?
    var tls: GRPCTLSConfiguration
    var authorityOverride: String?
    var requestCompression: GRPCCompressionPreference?
    var variables: [String: String]
    var secretVariables: [String: String]
}

struct GRPCStatus: Sendable, Equatable {
    var code: Int
    var message: String
    var detailsJSON: String?

    static let ok = GRPCStatus(code: 0, message: "OK")
}

struct GRPCMessageEvent: Sendable, Identifiable, Equatable {
    let id: UUID
    let sequence: Int
    let arrivedAt: Date
    let direction: Direction
    let json: String

    enum Direction: String, Sendable {
        case inbound
        case outbound
    }

    init(
        id: UUID = UUID(),
        sequence: Int,
        arrivedAt: Date = .now,
        direction: Direction,
        json: String
    ) {
        self.id = id
        self.sequence = sequence
        self.arrivedAt = arrivedAt
        self.direction = direction
        self.json = json
    }
}

struct GRPCResponseArtifact: Sendable, Identifiable {
    let id: UUID
    let requestID: UUID
    let startedAt: Date
    let finishedAt: Date?
    let target: String
    let serviceFullName: String
    let methodName: String
    let callShape: GRPCCallShape
    let streamState: GRPCStreamState
    let initialMetadata: [(String, String)]
    let trailingMetadata: [(String, String)]
    let messages: [GRPCMessageEvent]
    let status: GRPCStatus?
    let metrics: RequestMetrics?
    let error: GRPCExecutionError?
}

enum GRPCExecutionError: Error, Sendable, Equatable {
    case invalidTarget(String)
    case missingDefinition
    case unknownMethod(String)
    case invalidMessageJSON(String)
    case serialization(String)
    case transport(String)
    case status(GRPCStatus)
    case timeout
    case cancelled
    case schemaUnavailable(String)
    case validation([RequestValidationIssue])

    var title: String {
        switch self {
        case .invalidTarget: "Invalid target"
        case .missingDefinition: "Missing API definition"
        case .unknownMethod: "Unknown method"
        case .invalidMessageJSON: "Invalid message JSON"
        case .serialization: "Serialization error"
        case .transport: "Transport error"
        case .status: "gRPC status"
        case .timeout: "Deadline exceeded"
        case .cancelled: "Cancelled"
        case .schemaUnavailable: "Schema unavailable"
        case .validation: "Validation failed"
        }
    }

    var message: String {
        switch self {
        case .invalidTarget(let detail),
             .unknownMethod(let detail),
             .invalidMessageJSON(let detail),
             .serialization(let detail),
             .transport(let detail),
             .schemaUnavailable(let detail):
            return detail
        case .missingDefinition:
            return "Attach a protobuf API definition before sending."
        case .status(let status):
            return "\(status.code): \(status.message)"
        case .timeout:
            return "The RPC exceeded its deadline."
        case .cancelled:
            return "The RPC was cancelled."
        case .validation(let issues):
            return issues.map(\.message).joined(separator: "\n")
        }
    }
}
