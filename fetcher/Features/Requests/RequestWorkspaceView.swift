import SwiftData
import SwiftUI

struct RequestWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var commandCenter: AppCommandCenter
    @Bindable var workspace: RequestWorkspaceModel
    let request: RequestRecord?
    let secretStore: any SecretStore

    @State private var customMethod = ""
    @State private var showCustomMethod = false
    @State private var jsonError: String?
    @FocusState private var urlFocused: Bool

    private let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
    private let commonHeaders = [
        "Accept", "Authorization", "Content-Type", "User-Agent",
        "If-None-Match", "If-Modified-Since", "Cache-Control", "Origin", "Referer",
    ]

    var body: some View {
        Group {
            if let request, let project = request.project {
                VStack(spacing: 0) {
                    header(request: request, project: project)
                    Divider()
                    GeometryReader { geo in
                        VStack(spacing: 0) {
                            requestEditor(request: request, project: project)
                                .frame(height: max(180, geo.size.height * commandCenter.requestResponseSplit))
                            splitHandle(totalHeight: geo.size.height)
                            ResponseContainerView(
                                workspace: workspace,
                                selectedTab: $commandCenter.selectedResponseTab
                            )
                            .frame(maxHeight: .infinity)
                        }
                    }
                }
                .onAppear {
                    workspace.bind(requestID: request.id)
                    wireDraftBuilder(request: request, project: project)
                }
                .onChange(of: request.id) { _, _ in
                    workspace.bind(requestID: request.id)
                    wireDraftBuilder(request: request, project: project)
                }
                .onChange(of: commandCenter.focusURLToken) { _, _ in
                    urlFocused = true
                }
                .onChange(of: workspace.jsonFormatToken) { _, _ in
                    // Body editor observes via environment-less token; format in place if possible.
                    if let rest = request.restConfiguration, rest.bodyMode == .json {
                        if let formatted = try? RESTBodyEncoder.formatJSON(rest.bodyText) {
                            rest.bodyText = formatted
                            jsonError = nil
                            try? modelContext.save()
                        }
                    }
                }
            } else {
                EmptyStateView(
                    title: "No Request Selected",
                    message: "Create a project and request from the sidebar, or choose an existing request to edit and send."
                )
            }
        }
    }

    private func splitHandle(totalHeight: CGFloat) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(height: 4)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let y = value.location.y + (totalHeight * commandCenter.requestResponseSplit)
                        let ratio = min(0.85, max(0.25, y / max(totalHeight, 1)))
                        commandCenter.requestResponseSplit = ratio
                    }
            )
            .accessibilityLabel("Resize request and response")
    }

    @ViewBuilder
    private func header(request: RequestRecord, project: ProjectRecord) -> some View {
        let rest = bindingRest(for: request)
        HStack(spacing: 8) {
            Picker("Method", selection: Binding(
                get: {
                    methods.contains(rest.method) ? rest.method : "CUSTOM"
                },
                set: { selected in
                    if selected == "CUSTOM" {
                        customMethod = rest.method
                        showCustomMethod = true
                    } else {
                        rest.method = selected
                        touch(request)
                    }
                }
            )) {
                ForEach(methods, id: \.self) { Text($0).tag($0) }
                if !methods.contains(rest.method) {
                    Text(rest.method).tag("CUSTOM")
                }
                Divider()
                Text("Custom…").tag("CUSTOM")
            }
            .labelsHidden()
            .frame(width: 120)
            .accessibilityLabel("HTTP method")

            TextField("URL or path", text: Binding(
                get: { rest.endpoint },
                set: {
                    rest.endpoint = $0
                    touch(request)
                    syncPathParameters(request: request, endpoint: $0)
                }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
            .focused($urlFocused)
            .overlay(alignment: .trailing) {
                if !isEndpointPlausible(rest.endpoint, project: project) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("URL may be incomplete or invalid")
                        .padding(.trailing, 8)
                        .accessibilityLabel("Possibly invalid URL")
                }
            }

            Button {
                if workspace.executionState == .running {
                    workspace.cancel()
                } else {
                    workspace.send()
                }
            } label: {
                if workspace.executionState == .running {
                    Label("Stop", systemImage: "stop.fill")
                } else {
                    Label("Send", systemImage: "paperplane.fill")
                }
            }
            .help(workspace.executionState == .running ? "Cancel request" : "Send request")
            .accessibilityLabel(workspace.executionState == .running ? "Stop request" : "Send request")
        }
        .padding(12)
        .alert("Custom Method", isPresented: $showCustomMethod) {
            TextField("Method", text: $customMethod)
            Button("Cancel", role: .cancel) {}
            Button("Set") {
                let value = customMethod.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    rest.method = value.uppercased()
                    touch(request)
                }
            }
        }
    }

    @ViewBuilder
    private func requestEditor(request: RequestRecord, project: ProjectRecord) -> some View {
        VStack(spacing: 0) {
            Picker("Request section", selection: $commandCenter.selectedRequestTab) {
                ForEach(RequestEditorTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Group {
                switch commandCenter.selectedRequestTab {
                case .params:
                    ParamsEditorView(request: request)
                case .auth:
                    AuthEditorView(request: request, project: project, secretStore: secretStore)
                case .headers:
                    HeadersEditorView(request: request, suggestions: commonHeaders)
                case .body:
                    BodyEditorView(request: request, jsonError: $jsonError)
                case .settings:
                    RequestSettingsView(request: request, project: project)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func bindingRest(for request: RequestRecord) -> RESTRequestRecord {
        if let rest = request.restConfiguration {
            return rest
        }
        let rest = RESTRequestRecord(requestID: request.id)
        request.restConfiguration = rest
        modelContext.insert(rest)
        return rest
    }

    private func touch(_ request: RequestRecord) {
        request.updatedAt = .now
        try? modelContext.save()
    }

    private func isEndpointPlausible(_ endpoint: String, project: ProjectRecord) -> Bool {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed) != nil
        }
        let env = project.environments.first(where: { $0.id == project.selectedEnvironmentID })
        let base = (env?.baseURL.isEmpty == false ? env?.baseURL : project.baseURL) ?? ""
        return !base.isEmpty || trimmed.hasPrefix("/")
    }

    private func syncPathParameters(request: RequestRecord, endpoint: String) {
        let placeholders = RESTRequestValidator.pathPlaceholders(in: endpoint)
        let existing = request.parameters.filter { $0.kind == .path }
        for placeholder in placeholders {
            if !existing.contains(where: { $0.key == placeholder }) {
                let param = RequestParameterRecord(
                    kind: .path,
                    key: placeholder,
                    value: "",
                    sortIndex: Double(placeholders.firstIndex(of: placeholder) ?? 0),
                    request: request
                )
                modelContext.insert(param)
            }
        }
        try? modelContext.save()
    }

    private func wireDraftBuilder(request: RequestRecord, project: ProjectRecord) {
        let store = secretStore
        workspace.draftBuilder = {
            let environment = project.environments.first(where: { $0.id == project.selectedEnvironmentID })
            var secretValues: [UUID: String] = [:]
            if let environment {
                for variable in environment.variables where variable.isSecret {
                    if let refID = variable.secretReferenceID {
                        let reference = SecretReference(id: refID, label: variable.key)
                        if let data = try await store.read(reference),
                           let string = String(data: data, encoding: .utf8) {
                            secretValues[refID] = string
                        }
                    }
                }
            }
            if let auth = request.auth {
                for refID in auth.secretReferenceIDs {
                    let reference = SecretReference(id: refID, label: "auth")
                    if let data = try await store.read(reference),
                       let string = String(data: data, encoding: .utf8) {
                        secretValues[refID] = string
                    }
                }
            }
            for refID in project.defaultAuthSecretReferenceIDs {
                let reference = SecretReference(id: refID, label: "project-auth")
                if let data = try await store.read(reference),
                   let string = String(data: data, encoding: .utf8) {
                    secretValues[refID] = string
                }
            }
            return RequestDraftAssembler.makeDraft(
                request: request,
                project: project,
                environment: environment,
                secretValues: secretValues
            )
        }
    }
}
