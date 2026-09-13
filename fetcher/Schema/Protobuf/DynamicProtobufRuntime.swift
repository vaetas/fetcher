import Foundation

struct ProtobufTypeID: Hashable, Codable, Sendable {
    let fullName: String
}

struct ProtoFileDescriptor: Sendable, Hashable {
    let name: String
    let package: String
    let dependencies: [String]
}

struct ProtoMethodDescriptor: Sendable, Hashable {
    let serviceFullName: String
    let name: String
    let inputType: ProtobufTypeID
    let outputType: ProtobufTypeID
    let clientStreaming: Bool
    let serverStreaming: Bool
    let documentation: String?

    var fullMethodName: String {
        "\(serviceFullName)/\(name)"
    }

    var callShape: GRPCCallShape {
        switch (clientStreaming, serverStreaming) {
        case (false, false): .unary
        case (false, true): .serverStreaming
        case (true, false): .clientStreaming
        case (true, true): .bidirectionalStreaming
        }
    }
}

struct ProtoServiceDescriptor: Sendable, Hashable {
    let fullName: String
    let documentation: String?
    let methods: [ProtoMethodDescriptor]
}

struct ProtoFieldDescriptor: Sendable, Hashable {
    enum Cardinality: String, Sendable {
        case optional
        case required
        case repeated
        case map
    }

    let name: String
    let jsonName: String
    let number: Int
    let typeName: String
    let cardinality: Cardinality
    let oneofName: String?
    let documentation: String?
    let isDeprecated: Bool
}

struct ProtoEnumValueDescriptor: Sendable, Hashable {
    let name: String
    let number: Int
    let documentation: String?
}

struct ProtoEnumDescriptor: Sendable, Hashable {
    let fullName: String
    let values: [ProtoEnumValueDescriptor]
    let documentation: String?
}

struct ProtoMessageDescriptor: Sendable, Hashable {
    let fullName: String
    let fields: [ProtoFieldDescriptor]
    let nestedTypeNames: [String]
    let documentation: String?
}

struct ProtobufSchemaSnapshot: Sendable {
    let id: SchemaSnapshotID
    let files: [ProtoFileDescriptor]
    let servicesByName: [String: ProtoServiceDescriptor]
    let messagesByName: [String: ProtoMessageDescriptor]
    let enumsByName: [String: ProtoEnumDescriptor]
    let descriptorSetData: Data

    func method(serviceFullName: String, methodName: String) -> ProtoMethodDescriptor? {
        servicesByName[serviceFullName]?.methods.first { $0.name == methodName }
    }

    var allMethods: [ProtoMethodDescriptor] {
        servicesByName.values.flatMap(\.methods).sorted {
            $0.fullMethodName.localizedCaseInsensitiveCompare($1.fullMethodName) == .orderedAscending
        }
    }
}

struct ProtobufDiagnostic: Sendable, Equatable {
    var message: String
    var range: TextRange?
}

protocol DynamicProtobufRuntime: Sendable {
    func buildRegistry(descriptorSet: Data) throws -> ProtobufRegistry
    func validateJSON(
        _ json: String,
        messageType: ProtobufTypeID,
        registry: ProtobufRegistry
    ) -> [ProtobufDiagnostic]
    func encodeProtoJSON(
        _ json: String,
        messageType: ProtobufTypeID,
        registry: ProtobufRegistry
    ) throws -> Data
    func decodeToProtoJSON(
        _ protobuf: Data,
        messageType: ProtobufTypeID,
        registry: ProtobufRegistry
    ) throws -> String
}

struct ProtobufRegistry: Sendable {
    let snapshot: ProtobufSchemaSnapshot
}

protocol ProtoSchemaCompiler: Sendable {
    func compile(source: StagedProtoSource) async throws -> CompiledDescriptorSet
}

struct StagedProtoSource: Sendable {
    var rootFiles: [URL]
    var importRoots: [URL]
    var stagingRoot: URL
}

struct CompiledDescriptorSet: Sendable {
    var data: Data
    var diagnostics: [EditorDiagnostic]
}

enum ProtobufDescriptorIndex {
    static func build(from descriptorSetData: Data, id: SchemaSnapshotID = SchemaSnapshotID()) throws -> ProtobufSchemaSnapshot {
        try BuiltinDynamicProtobufRuntime().index(descriptorSet: descriptorSetData, id: id)
    }
}
