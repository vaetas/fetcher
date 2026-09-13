import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var localBookmarkData: Data?
    @State private var localProtoPaths: [String] = []
    @State private var localProtoBookmarkData: [Data] = []
    @State private var useAsProjectGraphQLSchema = true

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
                        Text(graphqlSourceKind.configurationDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if graphqlSourceKind == .remoteSDLURL {
                            Button("Use Literal Club Example") {
                                useLiteralClubExample()
                            }
                            .help("Prefill the hosted schema file supplied in the GraphQL example.")
                        }
                    case .protobuf:
                        Picker("Source kind", selection: $protobufSourceKind) {
                            ForEach(ProtobufDefinitionSourceKind.userSelectableCases, id: \.self) { sourceKind in
                                Text(sourceKind.displayName).tag(sourceKind)
                            }
                        }
                        sourceFields(for: protobufSourceKind)
                    }
                }

                if kind == .graphql {
                    Section("Project schema") {
                        Toggle("Use for all GraphQL requests in this project", isOn: $useAsProjectGraphQLSchema)
                        Text("One project schema drives validation, completion, and documentation for every nested GraphQL request.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add API Definition")
            .onChange(of: graphqlSourceKind) { _, _ in
                localPath = ""
                localBookmarkData = nil
            }
            .onChange(of: protobufSourceKind) { _, _ in
                localProtoPaths = []
                localProtoBookmarkData = []
            }
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
                return localBookmarkData != nil
            case .remoteSDLURL, .remoteIntrospectionJSONURL:
                return !remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case .protobuf:
            switch protobufSourceKind {
            case .serverReflection:
                return !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .localProtoFiles, .localProtoDirectory:
                return !localProtoBookmarkData.isEmpty
            case .localDescriptorSet:
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
            HStack {
                Text(localPath.isEmpty ? "No local source selected" : localPath)
                    .foregroundStyle(localPath.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(sourceKind == .localSDLDirectory ? "Choose Folder…" : "Choose File…") {
                    chooseLocalGraphQLSource(for: sourceKind)
                }
            }
        case .remoteSDLURL, .remoteIntrospectionJSONURL:
            TextField("Remote URL", text: $remoteURL)
                .textContentType(.URL)
        }
    }

    @ViewBuilder
    private func sourceFields(for sourceKind: ProtobufDefinitionSourceKind) -> some View {
        switch sourceKind {
        case .serverReflection:
            TextField("gRPC target (host:port)", text: $endpoint)
        case .localProtoFiles:
            localProtoSourcePicker
        case .localProtoDirectory:
            // Existing definitions retain this source kind, while newly created definitions use the
            // combined source picker above so files and folders can participate in one validation set.
            localProtoSourcePicker
        case .localDescriptorSet:
            TextField("Local path", text: $localPath)
        case .remoteProtoURL, .remoteDescriptorSetURL:
            TextField("Remote URL", text: $remoteURL)
        }
    }

    private var localProtoSourcePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if localProtoPaths.isEmpty {
                ContentUnavailableView(
                    "No gRPC sources selected",
                    systemImage: "folder.badge.questionmark",
                    description: Text("Choose one or more .proto files, folders, or a mixture of both.")
                )
            } else {
                ForEach(Array(localProtoPaths.enumerated()), id: \.offset) { index, path in
                    HStack {
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") {
                            localProtoPaths.remove(at: index)
                            localProtoBookmarkData.remove(at: index)
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Remove \(URL(fileURLWithPath: path).lastPathComponent)")
                    }
                }
            }

            HStack {
                Button(localProtoPaths.isEmpty ? "Choose Sources…" : "Add Sources…") {
                    chooseLocalProtoSources()
                }
                .help("Choose multiple folders and .proto files. Every selected folder is also an import root.")

                if !localProtoPaths.isEmpty {
                    Button("Clear") {
                        localProtoPaths = []
                        localProtoBookmarkData = []
                    }
                }
            }

            Text("Select every local contract source needed for validation. Folders are scanned recursively and become import roots. For an import such as \"acme/orders/v1/types.proto\", select the folder containing \"acme\". You can choose multiple roots, for example \"catalog-api/proto\" and \"shared-contracts/proto\", in one selection.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        if kind == .graphql, useAsProjectGraphQLSchema {
            project.setSharedGraphQLDefinition(definition.id)
        }
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
                GraphQLLocalSDLSource(bookmarkData: localBookmarkData, displayPath: localPath, isDirectory: false)
            )
            return try encoder.encode(config)
        case .localSDLDirectory:
            let config = GraphQLDefinitionConfig.localSDL(
                GraphQLLocalSDLSource(bookmarkData: localBookmarkData, displayPath: localPath, isDirectory: true)
            )
            return try encoder.encode(config)
        case .localIntrospectionJSON:
            let config = GraphQLDefinitionConfig.localIntrospectionJSON(
                GraphQLLocalIntrospectionJSONSource(bookmarkData: localBookmarkData, displayPath: localPath)
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
                    rootBookmarkData: localProtoBookmarkData,
                    importRootBookmarkData: [],
                    displayPaths: localProtoPaths,
                    importRootDisplayPaths: [],
                    isDirectory: false
                )
            )
            return try encoder.encode(config)
        case .localProtoDirectory:
            let config = ProtobufDefinitionConfig.localProto(
                GRPCLocalProtoSource(
                    rootBookmarkData: localProtoBookmarkData,
                    importRootBookmarkData: [],
                    displayPaths: localProtoPaths,
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

    private func chooseLocalGraphQLSource(for sourceKind: GraphQLDefinitionSourceKind) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = sourceKind != .localSDLDirectory
        panel.canChooseDirectories = sourceKind == .localSDLDirectory
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if sourceKind != .localSDLDirectory {
            if sourceKind == .localIntrospectionJSON {
                panel.allowedContentTypes = [.json]
            } else {
                panel.allowedContentTypes = [
                    UTType(filenameExtension: "graphql")!,
                    UTType(filenameExtension: "graphqls")!,
                    UTType(filenameExtension: "gql")!,
                ]
            }
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            localBookmarkData = try SecurityScopedBookmarkStore().makeBookmark(for: url)
            localPath = url.path
        } catch {
            localBookmarkData = nil
            localPath = ""
        }
    }

    private func chooseLocalProtoSources() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "proto")!]
        panel.prompt = localProtoPaths.isEmpty ? "Choose Sources" : "Add Sources"
        panel.message = "Choose all .proto files and folders required to validate this gRPC definition."

        guard panel.runModal() == .OK else { return }

        let bookmarkStore = SecurityScopedBookmarkStore()
        var selections: [(path: String, bookmark: Data)] = []
        for url in panel.urls {
            do {
                let bookmark = try bookmarkStore.makeBookmark(for: url)
                selections.append((url.path, bookmark))
            } catch {
                continue
            }
        }

        for selection in selections where !localProtoPaths.contains(selection.path) {
            localProtoPaths.append(selection.path)
            localProtoBookmarkData.append(selection.bookmark)
        }
    }

    private func useLiteralClubExample() {
        kind = .graphql
        graphqlSourceKind = .remoteSDLURL
        if trimmedName.isEmpty {
            name = "Literal Club"
        }
        remoteURL = "https://raw.githubusercontent.com/api-evangelist/literal/refs/heads/main/graphql/literal-schema.graphql"
        useAsProjectGraphQLSchema = true
    }
}
