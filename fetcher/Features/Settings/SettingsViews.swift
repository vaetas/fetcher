import SwiftData
import SwiftUI

struct RequestInspectorView: View {
    let request: RequestRecord?
    let preview: PreparedRequestPreview?

    var body: some View {
        Form {
            if let request {
                Section("Request") {
                    LabeledContent("Name", value: request.name)
                    LabeledContent("Protocol", value: request.protocolKind.displayName)
                    LabeledContent("ID", value: request.id.uuidString)
                    LabeledContent("Created", value: request.createdAt.formatted())
                    LabeledContent("Updated", value: request.updatedAt.formatted())
                }
                if let rest = request.restConfiguration {
                    Section("REST") {
                        LabeledContent("Method", value: rest.method)
                        LabeledContent("Endpoint", value: rest.endpoint)
                        LabeledContent("Body", value: rest.bodyMode.displayName)
                    }
                }
            } else {
                Text("Select a request to inspect metadata.")
                    .foregroundStyle(.secondary)
            }

            if let preview {
                Section("Resolved Preview") {
                    LabeledContent("URL", value: preview.resolvedURL)
                    ForEach(Array(preview.headers.enumerated()), id: \.offset) { _, header in
                        LabeledContent(header.0, value: header.1)
                    }
                    if !preview.warnings.isEmpty {
                        ForEach(preview.warnings) { warning in
                            Text(warning.message)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}

struct ProjectSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectRecord
    let secretStore: any SecretStore

    @State private var defaultHeaders: [KeyValueEntry] = []

    var body: some View {
        TabView {
            Form {
                TextField("Name", text: Binding(
                    get: { project.name },
                    set: {
                        project.name = $0
                        project.updatedAt = .now
                        try? modelContext.save()
                    }
                ))
                TextField("Default base URL", text: Binding(
                    get: { project.baseURL },
                    set: {
                        project.baseURL = $0
                        project.updatedAt = .now
                        try? modelContext.save()
                    }
                ))
                Picker("Default environment", selection: Binding(
                    get: { project.selectedEnvironmentID },
                    set: {
                        project.selectedEnvironmentID = $0
                        try? modelContext.save()
                    }
                )) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(project.environments.sorted(by: { $0.sortIndex < $1.sortIndex }), id: \.id) { environment in
                        Text(environment.name).tag(Optional(environment.id))
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Text("General") }

            EnvironmentEditorView(project: project, secretStore: secretStore)
                .tabItem { Text("Environments") }

            Form {
                Section("Default Headers") {
                    KeyValueEditor(entries: $defaultHeaders)
                    Button("Save Headers") { saveHeaders() }
                }
                Section("Default Auth") {
                    Picker("Type", selection: Binding(
                        get: { project.defaultAuthKind },
                        set: {
                            project.defaultAuthKind = $0
                            try? modelContext.save()
                        }
                    )) {
                        ForEach(AuthKind.allCases.filter { $0 != .inherit }, id: \.self) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                }
                Section("Networking") {
                    TextField(
                        "Timeout (seconds)",
                        value: Binding(
                            get: { project.defaultTimeoutSeconds },
                            set: {
                                project.defaultTimeoutSeconds = $0
                                try? modelContext.save()
                            }
                        ),
                        format: .number
                    )
                    Picker("Redirects", selection: Binding(
                        get: { project.defaultRedirectPolicy },
                        set: {
                            project.defaultRedirectPolicy = $0
                            try? modelContext.save()
                        }
                    )) {
                        ForEach(RedirectPolicy.allCases, id: \.self) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Text("Defaults") }
            .onAppear {
                defaultHeaders = (try? JSONDecoder().decode([KeyValueEntry].self, from: project.defaultHeadersJSON)) ?? []
            }
        }
        .padding()
    }

    private func saveHeaders() {
        project.defaultHeadersJSON = (try? JSONEncoder().encode(defaultHeaders)) ?? Data("[]".utf8)
        project.updatedAt = .now
        try? modelContext.save()
    }
}

struct AppSettingsView: View {
    var body: some View {
        Form {
            Section("Privacy") {
                Text("Fetcher is local-only. There is no account, cloud sync, analytics, or telemetry.")
                    .foregroundStyle(.secondary)
            }
            Section("Security") {
                Text("Secrets are stored in the macOS Keychain. ATS Option A allows arbitrary HTTP loads for API testing; see docs/ATS_SECURITY.md.")
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 280)
    }
}
