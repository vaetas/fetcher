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

    var configurationDescription: String {
        switch self {
        case .endpointIntrospection:
            "Ask a GraphQL endpoint for its current schema. Use this when the server permits introspection."
        case .localSDLFile:
            "Choose one local .graphql, .graphqls, or .gql schema file."
        case .localSDLDirectory:
            "Choose a folder of GraphQL schema files; Fetcher combines the supported files."
        case .localIntrospectionJSON:
            "Choose a saved JSON response containing a GraphQL __schema result."
        case .remoteSDLURL:
            "Download a schema-definition document from a URL. This is the option for a hosted .graphql file."
        case .remoteIntrospectionJSONURL:
            "Download a saved GraphQL introspection JSON response from a URL."
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

    static var userSelectableCases: [ProtobufDefinitionSourceKind] {
        allCases.filter { $0 != .localProtoDirectory }
    }

    var displayName: String {
        switch self {
        case .serverReflection: "Server Reflection"
        case .localProtoFiles: "Local Proto Sources"
        case .localProtoDirectory: "Local Proto Directory"
        case .localDescriptorSet: "Local Descriptor Set"
        case .remoteProtoURL: "Remote Proto URL"
        case .remoteDescriptorSetURL: "Remote Descriptor Set"
        }
    }
}
