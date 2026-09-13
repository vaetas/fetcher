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
    @State private var graphqlOperations: [GraphQLOperationInfo] = []
    @State private var graphqlSchema: GraphQLSchemaSnapshot?
    @State private var protobufSchema: ProtobufSchemaSnapshot?
    @FocusState private var urlFocused: Bool

    private let methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
    private let commonHeaders = [
        "Accept", "Authorization", "Content-Type", "User-Agent",
        "If-None-Match", "If-Modified-Since", "Cache-Control", "Origin", "Referer",
    ]
    private let languageService = GraphQLLanguageServiceFactory.makeDefault()

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
                            responsePane(request: request)
                                .frame(maxHeight: .infinity)
                        }
                    }
                }
                .onAppear {
                    workspace.bind(requestID: request.id, protocolKind: request.protocolKind)
                    wireDraftBuilder(request: request, project: project)
                    syncPathParametersIfNeeded(request: request)
                    refreshGraphQLIntelligence(request: request, project: project)
                    refreshProtobufSchema(request: request, project: project)
                }
                .onChange(of: request.id) { _, _ in
                    workspace.bind(requestID: request.id, protocolKind: request.protocolKind)
                    wireDraftBuilder(request: request, project: project)
                    syncPathParametersIfNeeded(request: request)
                    refreshGraphQLIntelligence(request: request, project: project)
                    refreshProtobufSchema(request: request, project: project)
                }
                .onChange(of: project.graphQLDefinitionSourceID) { _, _ in
                    refreshGraphQLIntelligence(request: request, project: project)
                }
                .onChange(of: commandCenter.focusURLToken) { _, _ in
                    urlFocused = true
                }
                .onChange(of: workspace.jsonFormatToken) { _, _ in
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

    @ViewBuilder
    private func responsePane(request: RequestRecord) -> some View {
        switch request.protocolKind {
        case .rest:
            ResponseContainerView(
                workspace: workspace,
                selectedTab: $commandCenter.selectedResponseTab
            )
        case .graphql:
            GraphQLResponseView(artifact: workspace.graphqlResponse)
        case .grpc:
            GRPCResponseView(artifact: workspace.grpcResponse)
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
        switch request.protocolKind {
        case .rest:
            restHeader(request: request, project: project)
        case .graphql:
            protocolSendHeader(title: "GraphQL", subtitle: request.graphqlConfiguration?.endpoint ?? "")
        case .grpc:
            protocolSendHeader(
                title: "gRPC",
                subtitle: [
                    request.grpcConfiguration?.serviceFullName,
                    request.grpcConfiguration?.methodName
                ]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "/")
            )
        }
    }

    private func protocolSendHeader(title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.headline)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            sendButton
        }
        .padding(12)
    }

    private var sendButton: some View {
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
        .disabled(workspace.schemaValidationBlocksSend && workspace.executionState != .running)
        .help(workspace.executionState == .running ? "Cancel request" : "Send request")
        .accessibilityLabel(workspace.executionState == .running ? "Stop request" : "Send request")
    }

    @ViewBuilder
    private func restHeader(request: RequestRecord, project: ProjectRecord) -> some View {
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

            sendButton
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
        switch request.protocolKind {
        case .rest:
            restEditor(request: request, project: project)
        case .graphql:
            GraphQLRequestEditor(
                request: request,
                project: project,
                secretStore: secretStore,
                sharedDefinition: project.graphQLDefinition,
                operations: graphqlOperations,
                diagnostics: workspace.editorDiagnostics,
                completionProvider: { document, offset in
                    guard let schema = graphqlSchema else { return [] }
                    return GraphQLCompletionEngine(languageService: languageService)
                        .completions(document: document, cursorUTF16Offset: offset, schema: schema)
                },
                onDocumentChange: { document in
                    scheduleGraphQLValidation(document: document)
                }
            )
        case .grpc:
            GRPCRequestEditor(
                request: request,
                definitions: project.apiDefinitions.filter { $0.kind == .protobuf },
                schemaSnapshot: protobufSchema,
                onInsertExampleBody: {
                    insertGRPCExampleBody(request: request)
                    if let json = request.grpcConfiguration?.bodyJSON {
                        scheduleProtoJSONValidation(json: json, request: request)
                    }
                }
            )
            .onChange(of: request.grpcConfiguration?.bodyJSON ?? "") { _, json in
                scheduleProtoJSONValidation(json: json, request: request)
            }
        }
    }

    private func restEditor(request: RequestRecord, project: ProjectRecord) -> some View {
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

    private func syncPathParametersIfNeeded(request: RequestRecord) {
        guard request.protocolKind == .rest,
              let endpoint = request.restConfiguration?.endpoint else { return }
        syncPathParameters(request: request, endpoint: endpoint)
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

    private func refreshGraphQLIntelligence(request: RequestRecord, project: ProjectRecord) {
        guard request.protocolKind == .graphql else { return }
        let document = request.graphqlConfiguration?.document ?? ""
        refreshGraphQLOperations(document: document)
        scheduleGraphQLValidation(document: document)
        Task {
            graphqlSchema = await loadGraphQLSchema(for: request, project: project)
        }
    }

    private func refreshGraphQLOperations(document: String) {
        graphqlOperations = (try? languageService.parseDocument(document))?.operations ?? []
    }

    private func scheduleGraphQLValidation(document: String) {
        let schema = graphqlSchema
        workspace.scheduleValidation(debounceMilliseconds: 300) {
            let parsed = try? languageService.parseDocument(document)
            let operations = parsed?.operations ?? []
            await MainActor.run {
                graphqlOperations = operations
            }

            var diagnostics = languageService.syntaxDiagnostics(in: document)
            var blocksSend = diagnostics.contains { $0.severity == .error }
            if let schema, let parsed {
                let schemaDiagnostics = languageService.validate(document: parsed, against: schema)
                diagnostics.append(contentsOf: schemaDiagnostics)
                if schemaDiagnostics.contains(where: { $0.severity == .error }) {
                    blocksSend = true
                }
            }
            return (diagnostics, blocksSend)
        }
    }

    private func loadGraphQLSchema(for request: RequestRecord, project: ProjectRecord) async -> GraphQLSchemaSnapshot? {
        guard let definitionID = project.graphQLDefinitionSourceID ?? request.graphqlConfiguration?.definitionSourceID,
              let definition = project.apiDefinitions.first(where: { $0.id == definitionID }),
              let fingerprint = definition.activeFingerprint else {
            return nil
        }
        do {
            let store = try SchemaArtifactStore()
            let data = try store.readNormalized(
                sourceID: definition.id,
                fingerprint: fingerprint,
                relativePath: "schema.graphql"
            )
            let sdl = String(data: data, encoding: .utf8) ?? ""
            return try languageService.loadSDL(sdl)
        } catch {
            return nil
        }
    }

    private func refreshProtobufSchema(request: RequestRecord, project: ProjectRecord) {
        guard request.protocolKind == .grpc else {
            protobufSchema = nil
            return
        }
        Task {
            protobufSchema = await loadProtobufSchema(for: request, project: project)
        }
    }

    private func loadProtobufSchema(for request: RequestRecord, project: ProjectRecord) async -> ProtobufSchemaSnapshot? {
        guard let definitionID = request.grpcConfiguration?.definitionSourceID,
              let definition = project.apiDefinitions.first(where: { $0.id == definitionID }),
              let fingerprint = definition.activeFingerprint else {
            return nil
        }
        do {
            let store = try SchemaArtifactStore()
            let data = try store.readNormalized(
                sourceID: definition.id,
                fingerprint: fingerprint,
                relativePath: "descriptor-set.pb"
            )
            return try ProtobufDescriptorIndex.build(from: data, id: SchemaSnapshotID(rawValue: definition.activeSnapshotID ?? UUID()))
        } catch {
            return nil
        }
    }

    private func insertGRPCExampleBody(request: RequestRecord) {
        guard let grpc = request.grpcConfiguration,
              let schema = protobufSchema,
              let method = schema.method(serviceFullName: grpc.serviceFullName, methodName: grpc.methodName),
              let message = schema.messagesByName[method.inputType.fullName.trimmingCharacters(in: CharacterSet(charactersIn: "."))]
                ?? schema.messagesByName[method.inputType.fullName] else {
            return
        }
        var object: [String: Any] = [:]
        for field in message.fields.prefix(12) {
            switch field.cardinality {
            case .repeated:
                object[field.jsonName] = []
            case .map:
                object[field.jsonName] = [String: Any]()
            default:
                if field.typeName.contains("bool") {
                    object[field.jsonName] = false
                } else if field.typeName.contains("string") || field.typeName.contains("bytes") {
                    object[field.jsonName] = ""
                } else if field.typeName.contains("int") || field.typeName.contains("fixed") || field.typeName.contains("double") || field.typeName.contains("float") {
                    object[field.jsonName] = 0
                } else {
                    object[field.jsonName] = [String: Any]()
                }
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            grpc.bodyJSON = text
            touch(request)
        }
    }

    private func scheduleProtoJSONValidation(json: String, request: RequestRecord) {
        let schema = protobufSchema
        let service = request.grpcConfiguration?.serviceFullName ?? ""
        let methodName = request.grpcConfiguration?.methodName ?? ""
        workspace.scheduleValidation {
            guard let schema,
                  let method = schema.method(serviceFullName: service, methodName: methodName) else {
                return ([], false)
            }
            let runtime = BuiltinDynamicProtobufRuntime()
            let registry = try? runtime.buildRegistry(descriptorSet: schema.descriptorSetData)
            guard let registry else { return ([], false) }
            let diagnostics = runtime.validateJSON(json, messageType: method.inputType, registry: registry)
                .map {
                    EditorDiagnostic(severity: .error, message: $0.message, range: $0.range, source: "protojson")
                }
            return (diagnostics, diagnostics.contains { $0.severity == .error })
        }
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
            return try RequestDraftAssembler.makeAPIDraft(
                request: request,
                project: project,
                environment: environment,
                secretValues: secretValues
            )
        }
    }
}
