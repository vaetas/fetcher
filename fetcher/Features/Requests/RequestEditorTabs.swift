import SwiftData
import SwiftUI

struct ParamsEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var request: RequestRecord

    var body: some View {
        ScrollView {
            Form {
                Section("Query") {
                    KeyValueEditor(entries: queryBinding)
                }
                Section("Path") {
                    KeyValueEditor(entries: pathBinding, keyPlaceholder: "Name", valuePlaceholder: "Value")
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    private var queryBinding: Binding<[KeyValueEntry]> {
        parameterBinding(kind: .query)
    }

    private var pathBinding: Binding<[KeyValueEntry]> {
        parameterBinding(kind: .path)
    }

    private func parameterBinding(kind: ParameterKind) -> Binding<[KeyValueEntry]> {
        Binding(
            get: {
                request.parameters
                    .filter { $0.kind == kind }
                    .sorted { $0.sortIndex < $1.sortIndex }
                    .map { KeyValueEntry(id: $0.id, key: $0.key, value: $0.value, isEnabled: $0.isEnabled) }
            },
            set: { newEntries in
                let existing = request.parameters.filter { $0.kind == kind }
                for item in existing {
                    modelContext.delete(item)
                }
                for (index, entry) in newEntries.enumerated() {
                    let record = RequestParameterRecord(
                        id: entry.id,
                        kind: kind,
                        key: entry.key,
                        value: entry.value,
                        isEnabled: entry.isEnabled,
                        sortIndex: Double(index),
                        request: request
                    )
                    modelContext.insert(record)
                }
                request.updatedAt = .now
                try? modelContext.save()
            }
        )
    }
}

struct HeadersEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var request: RequestRecord
    let suggestions: [String]

    var body: some View {
        ScrollView {
            Form {
                Section("Headers") {
                    KeyValueEditor(
                        entries: headerBinding,
                        keyPlaceholder: "Header",
                        valuePlaceholder: "Value",
                        keySuggestions: suggestions
                    )
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    private var headerBinding: Binding<[KeyValueEntry]> {
        Binding(
            get: {
                request.parameters
                    .filter { $0.kind == .header }
                    .sorted { $0.sortIndex < $1.sortIndex }
                    .map { KeyValueEntry(id: $0.id, key: $0.key, value: $0.value, isEnabled: $0.isEnabled) }
            },
            set: { newEntries in
                let existing = request.parameters.filter { $0.kind == .header }
                for item in existing {
                    modelContext.delete(item)
                }
                for (index, entry) in newEntries.enumerated() {
                    let record = RequestParameterRecord(
                        id: entry.id,
                        kind: .header,
                        key: entry.key,
                        value: entry.value,
                        isEnabled: entry.isEnabled,
                        sortIndex: Double(index),
                        request: request
                    )
                    modelContext.insert(record)
                }
                request.updatedAt = .now
                try? modelContext.save()
            }
        )
    }
}

struct BodyEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var request: RequestRecord
    @Binding var jsonError: String?

    var body: some View {
        let rest = ensureRest()
        VStack(alignment: .leading, spacing: 12) {
            Picker("Body mode", selection: Binding(
                get: { rest.bodyMode },
                set: {
                    rest.bodyMode = $0
                    request.updatedAt = .now
                    try? modelContext.save()
                    validateJSON()
                }
            )) {
                ForEach(RESTBodyMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if rest.bodyMode == .none {
                EmptyStateView(title: "No Body", message: "Choose JSON or Text to include a request body.")
            } else {
                if (rest.method.uppercased() == "GET" || rest.method.uppercased() == "HEAD"), !rest.bodyText.isEmpty {
                    Text("Warning: \(rest.method.uppercased()) with a body is unusual and may be rejected.")
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                }
                if let jsonError {
                    Text(jsonError)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
                NativeCodeEditor(text: Binding(
                    get: { rest.bodyText },
                    set: {
                        rest.bodyText = $0
                        request.updatedAt = .now
                        validateJSON()
                    }
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 8)
        .onAppear(perform: validateJSON)
    }

    private func ensureRest() -> RESTRequestRecord {
        if let rest = request.restConfiguration { return rest }
        let rest = RESTRequestRecord(requestID: request.id)
        request.restConfiguration = rest
        modelContext.insert(rest)
        return rest
    }

    private func validateJSON() {
        guard let rest = request.restConfiguration, rest.bodyMode == .json else {
            jsonError = nil
            return
        }
        let trimmed = rest.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            jsonError = nil
            return
        }
        guard let data = rest.bodyText.data(using: .utf8) else {
            jsonError = "JSON is not valid UTF-8."
            return
        }
        do {
            _ = try JSONSerialization.jsonObject(with: data)
            jsonError = nil
        } catch {
            jsonError = "Invalid JSON: \(error.localizedDescription)"
        }
    }

    func formatJSON() {
        guard let rest = request.restConfiguration, rest.bodyMode == .json else { return }
        do {
            rest.bodyText = try RESTBodyEncoder.formatJSON(rest.bodyText)
            jsonError = nil
            request.updatedAt = .now
            try? modelContext.save()
        } catch {
            jsonError = error.localizedDescription
        }
    }
}

struct RequestSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var request: RequestRecord
    let project: ProjectRecord

    var body: some View {
        let rest = ensureRest()
        ScrollView {
            Form {
                Section("Timeout") {
                Toggle("Use custom timeout", isOn: Binding(
                    get: { rest.timeoutSeconds != nil },
                    set: {
                        rest.timeoutSeconds = $0 ? (rest.timeoutSeconds ?? project.defaultTimeoutSeconds) : nil
                        save()
                    }
                ))
                if rest.timeoutSeconds != nil {
                    TextField(
                        "Seconds",
                        value: Binding(
                            get: { rest.timeoutSeconds ?? project.defaultTimeoutSeconds },
                            set: {
                                rest.timeoutSeconds = $0
                                save()
                            }
                        ),
                        format: .number
                    )
                } else {
                    Text("Project default: \(Int(project.defaultTimeoutSeconds))s")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Redirects") {
                Picker("Policy", selection: Binding(
                    get: { rest.redirectPolicy },
                    set: {
                        rest.redirectPolicy = $0
                        save()
                    }
                )) {
                    ForEach(RedirectPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
            }
            Section("Transport") {
                LabeledContent("Cache", value: CachePolicy.ignoreLocalCache.displayName)
                LabeledContent("Cookies", value: CookiePolicy.isolatedEphemeral.displayName)
                LabeledContent("TLS", value: TLSPolicy.systemDefault.displayName)
            }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    private func ensureRest() -> RESTRequestRecord {
        if let rest = request.restConfiguration { return rest }
        let rest = RESTRequestRecord(requestID: request.id)
        request.restConfiguration = rest
        modelContext.insert(rest)
        return rest
    }

    private func save() {
        request.updatedAt = .now
        try? modelContext.save()
    }
}
