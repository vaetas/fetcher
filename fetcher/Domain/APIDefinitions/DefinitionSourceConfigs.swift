import Foundation

struct EnabledKeyValue: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var key: String
    var value: String
    var isEnabled: Bool
    var isSecret: Bool
    var secretReferenceID: UUID?

    init(
        id: UUID = UUID(),
        key: String = "",
        value: String = "",
        isEnabled: Bool = true,
        isSecret: Bool = false,
        secretReferenceID: UUID? = nil
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
        self.isSecret = isSecret
        self.secretReferenceID = secretReferenceID
    }

    var asKeyValueEntry: KeyValueEntry {
        KeyValueEntry(id: id, key: key, value: value, isEnabled: isEnabled, isSecret: isSecret)
    }
}

struct GraphQLIntrospectionSource: Codable, Sendable, Equatable {
    var endpoint: String
    var headers: [EnabledKeyValue]
    var authenticationReferenceID: UUID?
}

struct GraphQLLocalSDLSource: Codable, Sendable, Equatable {
    var bookmarkData: Data?
    var displayPath: String
    var isDirectory: Bool
}

struct GraphQLLocalIntrospectionJSONSource: Codable, Sendable, Equatable {
    var bookmarkData: Data?
    var displayPath: String
}

struct GraphQLRemoteDocumentSource: Codable, Sendable, Equatable {
    var url: String
    var headers: [EnabledKeyValue]
    var authenticationReferenceID: UUID?
    var isIntrospectionJSON: Bool
}

enum GraphQLDefinitionConfig: Codable, Sendable, Equatable {
    case endpointIntrospection(GraphQLIntrospectionSource)
    case localSDL(GraphQLLocalSDLSource)
    case localIntrospectionJSON(GraphQLLocalIntrospectionJSONSource)
    case remoteDocument(GraphQLRemoteDocumentSource)

    var sourceKind: GraphQLDefinitionSourceKind {
        switch self {
        case .endpointIntrospection: .endpointIntrospection
        case .localSDL(let source): source.isDirectory ? .localSDLDirectory : .localSDLFile
        case .localIntrospectionJSON: .localIntrospectionJSON
        case .remoteDocument(let source):
            source.isIntrospectionJSON ? .remoteIntrospectionJSONURL : .remoteSDLURL
        }
    }
}

struct GRPCTLSConfiguration: Codable, Sendable, Equatable {
    var useTLS: Bool
    var authorityOverride: String?
    var serverNameOverride: String?

    static let plaintext = GRPCTLSConfiguration(useTLS: false)
    static let systemTLS = GRPCTLSConfiguration(useTLS: true)
}

struct GRPCReflectionSource: Codable, Sendable, Equatable {
    var endpoint: String
    var tls: GRPCTLSConfiguration
    var metadata: [EnabledKeyValue]
    var authenticationReferenceID: UUID?
}

struct GRPCLocalProtoSource: Codable, Sendable, Equatable {
    var rootBookmarkData: [Data]
    var importRootBookmarkData: [Data]
    var displayPaths: [String]
    var importRootDisplayPaths: [String]
    var isDirectory: Bool
}

struct GRPCLocalDescriptorSetSource: Codable, Sendable, Equatable {
    var bookmarkData: Data?
    var displayPath: String
}

struct GRPCRemoteProtoSource: Codable, Sendable, Equatable {
    var rootFiles: [String]
    var importRoots: [String]
    var headers: [EnabledKeyValue]
    var authenticationReferenceID: UUID?
}

struct GRPCRemoteDescriptorSetSource: Codable, Sendable, Equatable {
    var url: String
    var headers: [EnabledKeyValue]
    var authenticationReferenceID: UUID?
}

enum ProtobufDefinitionConfig: Codable, Sendable, Equatable {
    case serverReflection(GRPCReflectionSource)
    case localProto(GRPCLocalProtoSource)
    case localDescriptorSet(GRPCLocalDescriptorSetSource)
    case remoteProto(GRPCRemoteProtoSource)
    case remoteDescriptorSet(GRPCRemoteDescriptorSetSource)

    var sourceKind: ProtobufDefinitionSourceKind {
        switch self {
        case .serverReflection: .serverReflection
        case .localProto(let source): source.isDirectory ? .localProtoDirectory : .localProtoFiles
        case .localDescriptorSet: .localDescriptorSet
        case .remoteProto: .remoteProtoURL
        case .remoteDescriptorSet: .remoteDescriptorSetURL
        }
    }
}
