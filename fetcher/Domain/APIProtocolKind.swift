import Foundation

enum APIProtocolKind: String, Codable, CaseIterable, Sendable {
    case rest
    case graphql
    case grpc

    var displayName: String {
        switch self {
        case .rest: "REST"
        case .graphql: "GraphQL"
        case .grpc: "gRPC"
        }
    }
}
