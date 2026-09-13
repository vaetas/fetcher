import SwiftData
import SwiftUI

enum GraphQLRequestEditorTab: String, CaseIterable, Identifiable {
    case query
    case variables
    case headers
    case auth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .query: "Query"
        case .variables: "Variables"
        case .headers: "Headers"
        case .auth: "Auth"
        }
    }
}

struct GraphQLRequestEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var request: RequestRecord
    let project: ProjectRecord
    let secretStore: any SecretStore
    let definitions: [APIDefinitionRecord]
    let operations: [GraphQLOperationInfo]
    var diagnostics: [EditorDiagnostic] = []
    var completionProvider: ((String, Int) -> [CompletionItem])?
    var onDocumentChange: ((String) -> Void)?

    @State private var selectedTab: GraphQLRequestEditorTab = .query
    @State private var saveTask: Task<Void, Never>?

    private var graphqlDefinitions: [APIDefinitionRecord] {
        definitions.filter { $0.kind == .graphql }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            configurationBar
            Divider()
            Picker("Section", selection: $selectedTab) {
                ForEach(GraphQLRequestEditorTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Group {
                switch selectedTab {
                case .query:
                    queryEditor
                case .variables:
                    variablesEditor
                case .headers:
                    HeadersEditorView(request: request, suggestions: commonHeaderSuggestions)
                case .auth:
                    AuthEditorView(request: request, project: project, secretStore: secretStore)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear {
            saveTask?.cancel()
            flushSave()
        }
    }

    private var configurationBar: some View {
        Form {
            Section {
                TextField("Endpoint", text: endpointBinding)
                    .textFieldStyle(.roundedBorder)

                Picker("Method", selection: methodPreferenceBinding) {
                    ForEach(GraphQLHTTPMethodPreference.allCases, id: \.self) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                }

                if !graphqlDefinitions.isEmpty {
                    Picker("Definition", selection: definitionSourceBinding) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(graphqlDefinitions, id: \.id) { definition in
                            Text(definition.name).tag(Optional(definition.id))
                        }
                    }
                }

                if !operations.isEmpty {
                    Picker("Operation", selection: operationNameBinding) {
                        Text("Default").tag(Optional<String>.none)
                        ForEach(operationPickerOptions, id: \.self) { name in
                            Text(name).tag(Optional(name))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxHeight: 180)
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private var queryEditor: some View {
        IntelligentCodeEditor(
            text: documentBinding,
            syntaxMode: .graphql,
            diagnostics: diagnostics,
            completionProvider: completionProvider,
            onDebouncedChange: onDocumentChange
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var variablesEditor: some View {
        NativeCodeEditor(
            text: variablesJSONBinding,
            syntaxMode: .jsonWhenValid,
            contentIsJSON: true
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var operationPickerOptions: [String] {
        operations.compactMap(\.name)
    }

    private var commonHeaderSuggestions: [String] {
        ["Authorization", "Content-Type", "Accept", "X-Request-ID"]
    }

    private var documentBinding: Binding<String> {
        Binding(
            get: { ensureGraphQL().document },
            set: {
                ensureGraphQL().document = $0
                scheduleSave()
            }
        )
    }

    private var variablesJSONBinding: Binding<String> {
        Binding(
            get: { ensureGraphQL().variablesJSON },
            set: {
                ensureGraphQL().variablesJSON = $0
                scheduleSave()
            }
        )
    }

    private var endpointBinding: Binding<String> {
        Binding(
            get: { ensureGraphQL().endpoint },
            set: {
                ensureGraphQL().endpoint = $0
                scheduleSave()
            }
        )
    }

    private var methodPreferenceBinding: Binding<GraphQLHTTPMethodPreference> {
        Binding(
            get: { ensureGraphQL().methodPreference },
            set: {
                ensureGraphQL().methodPreference = $0
                flushSave()
            }
        )
    }

    private var definitionSourceBinding: Binding<UUID?> {
        Binding(
            get: { ensureGraphQL().definitionSourceID },
            set: {
                ensureGraphQL().definitionSourceID = $0
                flushSave()
            }
        )
    }

    private var operationNameBinding: Binding<String?> {
        Binding(
            get: { ensureGraphQL().operationName },
            set: {
                ensureGraphQL().operationName = $0
                flushSave()
            }
        )
    }

    private func ensureGraphQL() -> GraphQLRequestRecord {
        if let config = request.graphqlConfiguration { return config }
        let config = GraphQLRequestRecord(requestID: request.id)
        request.graphqlConfiguration = config
        modelContext.insert(config)
        return config
    }

    private func scheduleSave() {
        request.updatedAt = .now
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                try? modelContext.save()
            }
        }
    }

    private func flushSave() {
        saveTask?.cancel()
        request.updatedAt = .now
        try? modelContext.save()
    }
}
