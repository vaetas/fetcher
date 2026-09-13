import Foundation

enum APIDefinitionKind: String, Codable, Sendable, CaseIterable {
    case graphql
    case protobuf

    var displayName: String {
        switch self {
        case .graphql: "GraphQL"
        case .protobuf: "Protobuf / gRPC"
        }
    }
}

enum DefinitionRefreshPolicy: String, Codable, Sendable {
    case manual
}

enum DefinitionStatus: String, Codable, Sendable {
    case neverLoaded
    case loading
    case ready
    case staleWithError
    case unavailable

    var displayName: String {
        switch self {
        case .neverLoaded: "Never loaded"
        case .loading: "Loading"
        case .ready: "Ready"
        case .staleWithError: "Stale (refresh failed)"
        case .unavailable: "Unavailable"
        }
    }
}

struct DefinitionSourceID: Hashable, Codable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

struct SchemaSnapshotID: Hashable, Codable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

enum GraphQLDefinitionSourceKind: String, Codable, Sendable, CaseIterable {
    case endpointIntrospection
    case localSDLFile
    case localSDLDirectory
    case localIntrospectionJSON
    case remoteSDLURL
    case remoteIntrospectionJSONURL

    var displayName: String {
        switch self {
        case .endpointIntrospection: "Endpoint Introspection"
        case .localSDLFile: "Local SDL File"
        case .localSDLDirectory: "Local SDL Directory"
        case .localIntrospectionJSON: "Local Introspection JSON"
        case .remoteSDLURL: "Remote SDL URL"
        case .remoteIntrospectionJSONURL: "Remote Introspection JSON"
        }
    }
}

enum ProtobufDefinitionSourceKind: String, Codable, Sendable, CaseIterable {
    case serverReflection
    case localProtoFiles
    case localProtoDirectory
    case localDescriptorSet
    case remoteProtoURL
    case remoteDescriptorSetURL

    var displayName: String {
        switch self {
        case .serverReflection: "Server Reflection"
        case .localProtoFiles: "Local Proto Files"
        case .localProtoDirectory: "Local Proto Directory"
        case .localDescriptorSet: "Local Descriptor Set"
        case .remoteProtoURL: "Remote Proto URL"
        case .remoteDescriptorSetURL: "Remote Descriptor Set"
        }
    }
}
