import SwiftUI

struct DefinitionInspector: View {
    let definition: APIDefinitionRecord
    var onRefresh: () -> Void

    var body: some View {
        ScrollView {
            Form {
                Section("Definition") {
                    LabeledContent("Name", value: definition.name)
                    LabeledContent("Protocol", value: definition.kind.displayName)
                    LabeledContent("Source kind", value: definition.sourceKindRawValue)
                }

                Section("Status") {
                    HStack {
                        DefinitionStatusIndicator(status: definition.status)
                        Text(definition.status.displayName)
                    }
                    if let fingerprint = definition.activeFingerprint {
                        LabeledContent("Fingerprint") {
                            Text(fingerprint)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(2)
                        }
                    }
                    if let refreshed = definition.lastSuccessfulRefreshAt {
                        LabeledContent("Last refresh") {
                            Text(refreshed, format: .dateTime)
                        }
                    } else {
                        LabeledContent("Last refresh", value: "Never")
                    }
                    if let attempted = definition.lastAttemptAt {
                        LabeledContent("Last attempt") {
                            Text(attempted, format: .dateTime)
                        }
                    }
                    if let error = definition.lastErrorMessage, !error.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last error")
                                .foregroundStyle(.secondary)
                            Text(error)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Button {
                        onRefresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(definition.status == .loading)
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
    }
}

struct DefinitionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let definition: APIDefinitionRecord
    var onRefresh: () -> Void

    @State private var graphQLSchema: GraphQLSchemaSnapshot?
    @State private var schemaLoadError: String?

    var body: some View {
        NavigationStack {
            Group {
                if definition.kind == .graphql {
                    TabView {
                        DefinitionInspector(definition: definition, onRefresh: onRefresh)
                            .tabItem { Label("Details", systemImage: "info.circle") }

                        Group {
                            if let schemaLoadError {
                                ContentUnavailableView(
                                    "Schema Documentation Unavailable",
                                    systemImage: "doc.text.magnifyingglass",
                                    description: Text(schemaLoadError)
                                )
                            } else {
                                GraphQLSchemaBrowser(schema: graphQLSchema)
                            }
                        }
                        .tabItem { Label("Documentation", systemImage: "book") }
                    }
                } else {
                    DefinitionInspector(definition: definition, onRefresh: onRefresh)
                }
            }
            .navigationTitle(definition.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: definition.activeFingerprint) {
                await loadGraphQLSchema()
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    private func loadGraphQLSchema() async {
        guard definition.kind == .graphql else { return }
        guard let fingerprint = definition.activeFingerprint else {
            graphQLSchema = nil
            schemaLoadError = "Refresh this API definition to make its documentation available."
            return
        }

        let definitionID = definition.id
        let result = await Task.detached(priority: .userInitiated) {
            do {
                let store = try SchemaArtifactStore()
                let data = try store.readNormalized(
                    sourceID: definitionID,
                    fingerprint: fingerprint,
                    relativePath: "schema.graphql"
                )
                let source = String(decoding: data, as: UTF8.self)
                return Result<GraphQLSchemaSnapshot, Error>.success(
                    try BuiltinGraphQLLanguageService().loadSDL(source)
                )
            } catch {
                return Result<GraphQLSchemaSnapshot, Error>.failure(error)
            }
        }.value

        switch result {
        case .success(let schema):
            graphQLSchema = schema
            schemaLoadError = nil
        case .failure:
            graphQLSchema = nil
            schemaLoadError = "The saved schema snapshot could not be read. Refresh the API definition and try again."
        }
    }
}
