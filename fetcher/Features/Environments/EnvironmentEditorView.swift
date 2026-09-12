import SwiftData
import SwiftUI

struct EnvironmentEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectRecord
    let secretStore: any SecretStore

    @State private var selectedEnvironmentID: UUID?
    @State private var variableDrafts: [KeyValueEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Environment", selection: Binding(
                    get: { selectedEnvironmentID ?? project.selectedEnvironmentID },
                    set: { selectedEnvironmentID = $0 }
                )) {
                    ForEach(project.environments.sorted(by: { $0.sortIndex < $1.sortIndex }), id: \.id) { environment in
                        Text(environment.name).tag(Optional(environment.id))
                    }
                }
                Button("Add") { addEnvironment() }
                Button("Delete", role: .destructive) { deleteSelectedEnvironment() }
                    .disabled(project.environments.count <= 1)
            }

            if let environment = currentEnvironment {
                Form {
                    TextField("Name", text: Binding(
                        get: { environment.name },
                        set: {
                            environment.name = $0
                            try? modelContext.save()
                        }
                    ))
                    TextField("Base URL", text: Binding(
                        get: { environment.baseURL },
                        set: {
                            environment.baseURL = $0
                            try? modelContext.save()
                        }
                    ))
                    Section("Variables") {
                        KeyValueEditor(entries: $variableDrafts, showSecretToggle: true)
                        Button("Save Variables") {
                            Task { await saveVariables(for: environment) }
                        }
                    }
                }
                .formStyle(.grouped)
                .onAppear { loadVariables(from: environment) }
                .onChange(of: environment.id) { _, _ in loadVariables(from: environment) }
            }
        }
        .padding()
        .onAppear {
            selectedEnvironmentID = project.selectedEnvironmentID ?? project.environments.first?.id
        }
    }

    private var currentEnvironment: EnvironmentRecord? {
        let id = selectedEnvironmentID ?? project.selectedEnvironmentID
        return project.environments.first(where: { $0.id == id })
    }

    private func addEnvironment() {
        let environment = EnvironmentRecord(
            name: "Environment \(project.environments.count + 1)",
            baseURL: project.baseURL,
            sortIndex: (project.environments.map(\.sortIndex).max() ?? 0) + 1,
            project: project
        )
        modelContext.insert(environment)
        selectedEnvironmentID = environment.id
        project.selectedEnvironmentID = environment.id
        try? modelContext.save()
    }

    private func deleteSelectedEnvironment() {
        guard let environment = currentEnvironment, project.environments.count > 1 else { return }
        modelContext.delete(environment)
        selectedEnvironmentID = project.environments.first?.id
        project.selectedEnvironmentID = selectedEnvironmentID
        try? modelContext.save()
    }

    private func loadVariables(from environment: EnvironmentRecord) {
        variableDrafts = environment.variables
            .sorted { $0.sortIndex < $1.sortIndex }
            .map {
                KeyValueEntry(
                    id: $0.id,
                    key: $0.key,
                    value: $0.isSecret ? "" : ($0.value ?? ""),
                    isEnabled: $0.isEnabled,
                    isSecret: $0.isSecret
                )
            }
        Task {
            for index in variableDrafts.indices where variableDrafts[index].isSecret {
                if let record = environment.variables.first(where: { $0.id == variableDrafts[index].id }),
                   let ref = record.secretReferenceID,
                   let data = try? await secretStore.read(SecretReference(id: ref, label: record.key)),
                   let value = String(data: data, encoding: .utf8) {
                    variableDrafts[index].value = value
                }
            }
        }
    }

    private func saveVariables(for environment: EnvironmentRecord) async {
        for existing in environment.variables {
            modelContext.delete(existing)
        }
        for (index, draft) in variableDrafts.enumerated() {
            var secretReferenceID: UUID?
            var value: String? = draft.value
            if draft.isSecret {
                let reference = SecretReference(label: draft.key)
                secretReferenceID = reference.id
                if let data = draft.value.data(using: .utf8) {
                    try? await secretStore.write(data, reference: reference)
                }
                value = nil
            }
            let record = EnvironmentVariableRecord(
                id: draft.id,
                key: draft.key,
                value: value,
                secretReferenceID: secretReferenceID,
                isSecret: draft.isSecret,
                isEnabled: draft.isEnabled,
                sortIndex: Double(index),
                environment: environment
            )
            modelContext.insert(record)
        }
        try? modelContext.save()
    }
}
