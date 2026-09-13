import SwiftData
import SwiftUI

struct AddAPIDefinitionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let project: ProjectRecord
    var onAdded: ((APIDefinitionRecord) -> Void)?

    @State private var name = ""
    @State private var kind: APIDefinitionKind = .graphql
    @State private var graphqlSourceKind: GraphQLDefinitionSourceKind = .endpointIntrospection
    @State private var protobufSourceKind: ProtobufDefinitionSourceKind = .serverReflection
    @State private var endpoint = ""
    @State private var remoteURL = ""
    @State private var localPath = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Definition") {
                    TextField("Name", text: $name)
                    Picker("Protocol", selection: $kind) {
                        ForEach(APIDefinitionKind.allCases, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                }

                Section("Source") {
                    switch kind {
                    case .graphql:
                        Picker("Source kind", selection: $graphqlSourceKind) {
                            ForEach(GraphQLDefinitionSourceKind.allCases, id: \.self) { sourceKind in
                                Text(sourceKind.displayName).tag(sourceKind)
                            }
                        }
                        sourceFields(for: graphqlSourceKind)
                    case .protobuf:
                        Picker("Source kind", selection: $protobufSourceKind) {
                            ForEach(ProtobufDefinitionSourceKind.allCases, id: \.self) { sourceKind in
                                Text(sourceKind.displayName).tag(sourceKind)
                            }
                        }
                        sourceFields(for: protobufSourceKind)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add API Definition")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addDefinition() }
                        .disabled(trimmedName.isEmpty || !hasRequiredSourceFields)
                }
            }
            .frame(minWidth: 420, minHeight: 320)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasRequiredSourceFields: Bool {
        switch kind {
        case .graphql:
            switch graphqlSourceKind {
            case .endpointIntrospection:
                return !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .localSDLFile, .localSDLDirectory, .localIntrospectionJSON:
                return !localPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .remoteSDLURL, .remoteIntrospectionJSONURL:
                return !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case .protobuf:
            switch protobufSourceKind {
            case .serverReflection:
                return !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .localProtoFiles, .localProtoDirectory, .localDescriptorSet:
                return !localPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .remoteProtoURL, .remoteDescriptorSetURL:
                return !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    @ViewBuilder
    private func sourceFields(for sourceKind: GraphQLDefinitionSourceKind) -> some View {
        switch sourceKind {
        case .endpointIntrospection:
            TextField("GraphQL endpoint", text: $endpoint)
        case .localSDLFile, .localSDLDirectory, .localIntrospectionJSON:
            TextField("Local path", text: $localPath)
        case .remoteSDLURL, .remoteIntrospectionJSONURL:
            TextField("Remote URL", text: $remoteURL)
        }
    }

    @ViewBuilder
    private func sourceFields(for sourceKind: ProtobufDefinitionSourceKind) -> some View {
        switch sourceKind {
        case .serverReflection:
            TextField("gRPC target (host:port)", text: $endpoint)
        case .localProtoFiles, .localProtoDirectory, .localDescriptorSet:
            TextField("Local path", text: $localPath)
        case .remoteProtoURL, .remoteDescriptorSetURL:
            TextField("Remote URL", text: $remoteURL)
        }
    }

    private func addDefinition() {
        guard hasRequiredSourceFields else { return }
        let configData: Data
        let sourceKindRaw: String
        do {
            switch kind {
            case .graphql:
                sourceKindRaw = graphqlSourceKind.rawValue
                configData = try encodeGraphQLConfig()
            case .protobuf:
                sourceKindRaw = protobufSourceKind.rawValue
                configData = try encodeProtobufConfig()
            }
        } catch {
            return
        }

        let definition = APIDefinitionRecord(
            projectID: project.id,
            name: trimmedName,
            kind: kind,
            sourceKindRawValue: sourceKindRaw,
            configJSON: configData,
            sortIndex: (project.apiDefinitions.map(\.sortIndex).max() ?? 0) + 1,
            project: project
        )
        modelContext.insert(definition)
        project.updatedAt = .now
        try? modelContext.save()
        onAdded?(definition)
        dismiss()
    }

    private func encodeGraphQLConfig() throws -> Data {
        let encoder = JSONEncoder()
        switch graphqlSourceKind {
        case .endpointIntrospection:
            let config = GraphQLDefinitionConfig.endpointIntrospection(
                GraphQLIntrospectionSource(endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines), headers: [])
            )
            return try encoder.encode(config)
        case .localSDLFile:
            let config = GraphQLDefinitionConfig.localSDL(
                GraphQLLocalSDLSource(bookmarkData: nil, displayPath: localPath, isDirectory: false)
            )
            return try encoder.encode(config)
        case .localSDLDirectory:
            let config = GraphQLDefinitionConfig.localSDL(
                GraphQLLocalSDLSource(bookmarkData: nil, displayPath: localPath, isDirectory: true)
            )
            return try encoder.encode(config)
        case .localIntrospectionJSON:
            let config = GraphQLDefinitionConfig.localIntrospectionJSON(
                GraphQLLocalIntrospectionJSONSource(bookmarkData: nil, displayPath: localPath)
            )
            return try encoder.encode(config)
        case .remoteSDLURL:
            let config = GraphQLDefinitionConfig.remoteDocument(
                GraphQLRemoteDocumentSource(url: remoteURL, headers: [], authenticationReferenceID: nil, isIntrospectionJSON: false)
            )
            return try encoder.encode(config)
        case .remoteIntrospectionJSONURL:
            let config = GraphQLDefinitionConfig.remoteDocument(
                GraphQLRemoteDocumentSource(url: remoteURL, headers: [], authenticationReferenceID: nil, isIntrospectionJSON: true)
            )
            return try encoder.encode(config)
        }
    }

    private func encodeProtobufConfig() throws -> Data {
        let encoder = JSONEncoder()
        switch protobufSourceKind {
        case .serverReflection:
            let config = ProtobufDefinitionConfig.serverReflection(
                GRPCReflectionSource(
                    endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                    tls: .plaintext,
                    metadata: []
                )
            )
            return try encoder.encode(config)
        case .localProtoFiles:
            let config = ProtobufDefinitionConfig.localProto(
                GRPCLocalProtoSource(
                    rootBookmarkData: [],
                    importRootBookmarkData: [],
                    displayPaths: [localPath],
                    importRootDisplayPaths: [],
                    isDirectory: false
                )
            )
            return try encoder.encode(config)
        case .localProtoDirectory:
            let config = ProtobufDefinitionConfig.localProto(
                GRPCLocalProtoSource(
                    rootBookmarkData: [],
                    importRootBookmarkData: [],
                    displayPaths: [localPath],
                    importRootDisplayPaths: [],
                    isDirectory: true
                )
            )
            return try encoder.encode(config)
        case .localDescriptorSet:
            let config = ProtobufDefinitionConfig.localDescriptorSet(
                GRPCLocalDescriptorSetSource(bookmarkData: nil, displayPath: localPath)
            )
            return try encoder.encode(config)
        case .remoteProtoURL:
            let config = ProtobufDefinitionConfig.remoteProto(
                GRPCRemoteProtoSource(rootFiles: [remoteURL], importRoots: [], headers: [], authenticationReferenceID: nil)
            )
            return try encoder.encode(config)
        case .remoteDescriptorSetURL:
            let config = ProtobufDefinitionConfig.remoteDescriptorSet(
                GRPCRemoteDescriptorSetSource(url: remoteURL, headers: [], authenticationReferenceID: nil)
            )
            return try encoder.encode(config)
        }
    }
}
