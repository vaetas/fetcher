import SwiftData
import SwiftUI

struct ProjectSidebarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProjectRecord.sortIndex) private var projects: [ProjectRecord]
    @Bindable var commandCenter: AppCommandCenter
    var onSelectRequest: (RequestRecord) -> Void
    var onOpenProjectSettings: (ProjectRecord) -> Void

    @State private var renamingProjectID: UUID?
    @State private var renamingRequestID: UUID?
    @State private var draftName = ""
    @State private var confirmDeleteProject: ProjectRecord?
    @State private var confirmDeleteRequest: RequestRecord?
    @State private var showAddDefinitionForProject: ProjectRecord?
    @State private var selectedDefinitionID: UUID?
    @State private var definitionRefreshCoordinator: DefinitionRefreshCoordinator?
    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        List(selection: Binding(
            get: { commandCenter.selectedRequestID },
            set: { newValue in
                commandCenter.selectedRequestID = newValue
                if let id = newValue,
                   let request = projects.flatMap(\.requests).first(where: { $0.id == id }) {
                    commandCenter.selectedProjectID = request.project?.id
                    onSelectRequest(request)
                }
            }
        )) {
            Section("Projects") {
                ForEach(filteredProjects, id: \.id) { project in
                    projectRow(project)
                        .contextMenu {
                            projectContextMenu(project)
                        }

                    if isExpanded(project) {
                        ForEach(filteredRequests(for: project), id: \.id) { request in
                            requestRow(request)
                                .tag(request.id)
                                .contextMenu {
                                    requestContextMenu(request)
                                }
                        }
                        .onMove { indices, newOffset in
                            reorderRequests(in: project, from: indices, to: newOffset)
                        }

                        APIDefinitionsSidebarSection(
                            project: project,
                            selectedDefinitionID: $selectedDefinitionID,
                            onRefresh: { definition in
                                Task { await refreshDefinition(definition) }
                            },
                            onAdd: {
                                showAddDefinitionForProject = project
                            },
                            onUseForProjectGraphQL: { definition in
                                project.setSharedGraphQLDefinition(definition.id)
                                try? modelContext.save()
                            }
                        )
                    }
                }
                .onMove(perform: reorderProjects)
            }
        }
        .listStyle(.sidebar)
        .frame(maxHeight: .infinity)
        .searchable(text: $commandCenter.searchText, placement: .sidebar, prompt: "Search requests")
        .onChange(of: commandCenter.renameSelectedRequestToken) { _, _ in
            renameSelectedRequest()
        }
        .sheet(isPresented: Binding(
            get: { renamingRequestID != nil },
            set: { if !$0 { cancelRequestRename() } }
        )) {
            RenameNameSheet(
                title: "Rename Request",
                name: $draftName,
                onConfirm: commitRequestRename,
                onCancel: cancelRequestRename
            )
        }
        .sheet(isPresented: Binding(
            get: { showAddDefinitionForProject != nil },
            set: { if !$0 { showAddDefinitionForProject = nil } }
        )) {
            if let project = showAddDefinitionForProject {
                AddAPIDefinitionSheet(project: project) { definition in
                    selectedDefinitionID = definition.id
                    showAddDefinitionForProject = nil
                    Task { await refreshDefinition(definition) }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedDefinition != nil },
            set: { if !$0 { selectedDefinitionID = nil } }
        )) {
            if let definition = selectedDefinition {
                DefinitionDetailSheet(
                    definition: definition,
                    onRefresh: { Task { await refreshDefinition(definition) } }
                )
            }
        }
        .confirmationDialog(
            "Delete Project?",
            isPresented: Binding(
                get: { confirmDeleteProject != nil },
                set: { if !$0 { confirmDeleteProject = nil } }
            ),
            presenting: confirmDeleteProject
        ) { project in
            Button("Delete", role: .destructive) {
                delete(project)
            }
            Button("Cancel", role: .cancel) {}
        } message: { project in
            Text("Delete “\(project.name)” and all of its requests?")
        }
        .confirmationDialog(
            "Delete Request?",
            isPresented: Binding(
                get: { confirmDeleteRequest != nil },
                set: { if !$0 { confirmDeleteRequest = nil } }
            ),
            presenting: confirmDeleteRequest
        ) { request in
            Button("Delete", role: .destructive) {
                delete(request)
            }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text("Delete “\(request.name)”?")
        }
        .task {
            await ensureRefreshCoordinator()
        }
    }

    private var filteredProjects: [ProjectRecord] {
        let query = commandCenter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projects }
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || filteredRequests(for: project).isEmpty == false
        }
    }

    private var selectedDefinition: APIDefinitionRecord? {
        guard let selectedDefinitionID else { return nil }
        return projects
            .flatMap(\.apiDefinitions)
            .first(where: { $0.id == selectedDefinitionID })
    }

    private func filteredRequests(for project: ProjectRecord) -> [RequestRecord] {
        let requests = project.requests.sorted { $0.sortIndex < $1.sortIndex }
        let query = commandCenter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return requests }
        return requests.filter { request in
            request.name.localizedCaseInsensitiveContains(query)
                || (request.restConfiguration?.endpoint.localizedCaseInsensitiveContains(query) ?? false)
                || (request.restConfiguration?.method.localizedCaseInsensitiveContains(query) ?? false)
                || (request.graphqlConfiguration?.endpoint.localizedCaseInsensitiveContains(query) ?? false)
                || (request.grpcConfiguration?.serviceFullName.localizedCaseInsensitiveContains(query) ?? false)
                || project.name.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private func projectRow(_ project: ProjectRecord) -> some View {
        if renamingProjectID == project.id {
            TextField("Project name", text: $draftName)
                .textFieldStyle(.plain)
                .focused($renameFieldFocused)
                .onSubmit { commitProjectRename() }
                .onExitCommand { cancelProjectRename() }
        } else {
            HStack(spacing: 6) {
                Button {
                    toggleExpansion(for: project)
                } label: {
                    Image(systemName: isExpanded(project) ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 12, height: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded(project) ? "Collapse \(project.name)" : "Expand \(project.name)")

                Label {
                    Text(project.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    Image(systemName: "folder")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                beginProjectRename(project)
            }
        }
    }

    @ViewBuilder
    private func requestRow(_ request: RequestRecord) -> some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: 18)
                .accessibilityHidden(true)

            MethodBadge(method: badgeLabel(for: request))
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle = subtitle(for: request), !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            select(request)
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            beginRequestRename(request)
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel(requestAccessibilityLabel(for: request))
    }

    private func select(_ request: RequestRecord) {
        commandCenter.selectedRequestID = request.id
        commandCenter.selectedProjectID = request.project?.id
        onSelectRequest(request)
    }

    private func isExpanded(_ project: ProjectRecord) -> Bool {
        commandCenter.expandedProjectIDs.contains(project.id)
    }

    private func toggleExpansion(for project: ProjectRecord) {
        if isExpanded(project) {
            commandCenter.expandedProjectIDs.remove(project.id)
        } else {
            commandCenter.expandedProjectIDs.insert(project.id)
        }
    }

    @ViewBuilder
    private func projectContextMenu(_ project: ProjectRecord) -> some View {
        Button("New REST Request") {
            commandCenter.selectedProjectID = project.id
            createRequest(in: project, kind: .rest)
        }
        Button("New GraphQL Request") {
            commandCenter.selectedProjectID = project.id
            createRequest(in: project, kind: .graphql)
        }
        Button("New gRPC Request") {
            commandCenter.selectedProjectID = project.id
            createRequest(in: project, kind: .grpc)
        }
        Button("Add API Definition…") {
            commandCenter.selectedProjectID = project.id
            showAddDefinitionForProject = project
        }
        Button("Rename") {
            beginProjectRename(project)
        }
        Button("Project Settings") {
            commandCenter.selectedProjectID = project.id
            onOpenProjectSettings(project)
        }
        Divider()
        Button("Delete Project", role: .destructive) {
            confirmDeleteProject = project
        }
    }

    @ViewBuilder
    private func requestContextMenu(_ request: RequestRecord) -> some View {
        Button("Duplicate") { duplicate(request) }
        Button("Rename") {
            beginRequestRename(request)
        }
        Divider()
        Button("Delete Request", role: .destructive) {
            confirmDeleteRequest = request
        }
    }

    private func requestAccessibilityLabel(for request: RequestRecord) -> String {
        let name = RequestRecord.displayName(for: request.name)
        if let subtitle = subtitle(for: request), !subtitle.isEmpty {
            return "\(badgeLabel(for: request)) request, \(name), \(subtitle)"
        }
        return "\(badgeLabel(for: request)) request, \(name)"
    }

    private func badgeLabel(for request: RequestRecord) -> String {
        switch request.protocolKind {
        case .rest: request.restConfiguration?.method ?? "GET"
        case .graphql: "GQL"
        case .grpc: "RPC"
        }
    }

    private func subtitle(for request: RequestRecord) -> String? {
        switch request.protocolKind {
        case .rest: request.restConfiguration?.endpoint
        case .graphql: request.graphqlConfiguration?.endpoint
        case .grpc:
            [request.grpcConfiguration?.serviceFullName, request.grpcConfiguration?.methodName]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "/")
        }
    }

    private func renameSelectedRequest() {
        guard let id = commandCenter.selectedRequestID,
              let request = projects.flatMap(\.requests).first(where: { $0.id == id }) else { return }
        beginRequestRename(request)
    }

    private func beginProjectRename(_ project: ProjectRecord) {
        cancelRequestRename()
        renamingProjectID = project.id
        draftName = project.name
        renameFieldFocused = true
    }

    private func commitProjectRename() {
        guard let id = renamingProjectID,
              let project = projects.first(where: { $0.id == id }) else {
            cancelProjectRename()
            return
        }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            project.name = trimmed
            project.updatedAt = .now
            try? modelContext.save()
        }
        cancelProjectRename()
    }

    private func cancelProjectRename() {
        renamingProjectID = nil
        renameFieldFocused = false
    }

    private func beginRequestRename(_ request: RequestRecord) {
        cancelProjectRename()
        commandCenter.selectedRequestID = request.id
        commandCenter.selectedProjectID = request.project?.id
        renamingRequestID = request.id
        draftName = request.name
    }

    private func commitRequestRename() {
        guard let id = renamingRequestID,
              let request = projects.flatMap(\.requests).first(where: { $0.id == id }) else {
            cancelRequestRename()
            return
        }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            request.name = trimmed
            request.updatedAt = .now
            try? modelContext.save()
        }
        cancelRequestRename()
    }

    private func cancelRequestRename() {
        renamingRequestID = nil
    }

    func createProject() {
        let project = ProjectRecord(name: "New Project", sortIndex: (projects.map(\.sortIndex).max() ?? 0) + 1)
        let environment = EnvironmentRecord(name: "Development", baseURL: "http://localhost:8787", project: project)
        project.environments = [environment]
        project.selectedEnvironmentID = environment.id
        modelContext.insert(project)
        modelContext.insert(environment)
        commandCenter.selectedProjectID = project.id
        commandCenter.expandedProjectIDs.insert(project.id)
        createRequest(in: project, kind: .rest)
        try? modelContext.save()
    }

    func createRequest(in project: ProjectRecord? = nil, kind: APIProtocolKind = .rest) {
        let target = project ?? projects.first(where: { $0.id == commandCenter.selectedProjectID }) ?? projects.first
        guard let target else {
            createProject()
            return
        }
        let request = RequestRecord(
            name: RequestRecord.defaultName,
            protocolKind: kind,
            sortIndex: (target.requests.map(\.sortIndex).max() ?? 0) + 1,
            project: target
        )
        let auth = RequestAuthRecord(requestID: request.id)
        request.auth = auth
        modelContext.insert(request)
        modelContext.insert(auth)

        switch kind {
        case .rest:
            let rest = RESTRequestRecord(requestID: request.id)
            request.restConfiguration = rest
            modelContext.insert(rest)
        case .graphql:
            let graphql = GraphQLRequestRecord(requestID: request.id, endpoint: target.baseURL.isEmpty ? "http://localhost:4000/graphql" : "\(target.baseURL)/graphql")
            graphql.definitionSourceID = target.graphQLDefinitionSourceID
            request.graphqlConfiguration = graphql
            modelContext.insert(graphql)
        case .grpc:
            let grpc = GRPCRequestRecord(requestID: request.id)
            request.grpcConfiguration = grpc
            modelContext.insert(grpc)
        }

        commandCenter.selectedProjectID = target.id
        commandCenter.selectedRequestID = request.id
        commandCenter.expandedProjectIDs.insert(target.id)
        onSelectRequest(request)
        try? modelContext.save()
    }

    func duplicateSelectedRequest() {
        guard let id = commandCenter.selectedRequestID,
              let request = projects.flatMap(\.requests).first(where: { $0.id == id }) else { return }
        duplicate(request)
    }

    private func duplicate(_ request: RequestRecord) {
        guard let project = request.project else { return }
        let copy = RequestRecord(
            name: "\(request.name) Copy",
            protocolKind: request.protocolKind,
            sortIndex: (project.requests.map(\.sortIndex).max() ?? 0) + 1,
            project: project
        )
        let authSource = request.auth
        let auth = RequestAuthRecord(
            requestID: copy.id,
            authType: authSource?.authKind ?? .none,
            nonSecretJSON: authSource?.nonSecretJSON ?? Data("{}".utf8),
            secretReferenceIDs: authSource?.secretReferenceIDs ?? []
        )
        copy.auth = auth
        modelContext.insert(copy)
        modelContext.insert(auth)

        switch request.protocolKind {
        case .rest:
            let restSource = request.restConfiguration
            let rest = RESTRequestRecord(
                requestID: copy.id,
                method: restSource?.method ?? "GET",
                endpoint: restSource?.endpoint ?? "/",
                bodyMode: restSource?.bodyMode ?? .none,
                bodyText: restSource?.bodyText ?? "",
                timeoutSeconds: restSource?.timeoutSeconds,
                redirectPolicy: restSource?.redirectPolicy ?? .follow
            )
            copy.restConfiguration = rest
            modelContext.insert(rest)
        case .graphql:
            let source = request.graphqlConfiguration
            let graphql = GraphQLRequestRecord(
                requestID: copy.id,
                endpoint: source?.endpoint ?? "",
                document: source?.document ?? "query {\n  \n}\n",
                variablesJSON: source?.variablesJSON ?? "{}",
                methodPreference: source?.methodPreference ?? .post
            )
            graphql.definitionSourceID = project.graphQLDefinitionSourceID ?? source?.definitionSourceID
            graphql.operationName = source?.operationName
            graphql.extensionsJSON = source?.extensionsJSON
            copy.graphqlConfiguration = graphql
            modelContext.insert(graphql)
        case .grpc:
            let source = request.grpcConfiguration
            let grpc = GRPCRequestRecord(
                requestID: copy.id,
                target: source?.target ?? "localhost:50051",
                serviceFullName: source?.serviceFullName ?? "",
                methodName: source?.methodName ?? "",
                bodyJSON: source?.bodyJSON ?? "{}"
            )
            grpc.definitionSourceID = source?.definitionSourceID
            grpc.outboundMessages = source?.outboundMessages ?? []
            grpc.deadlineSeconds = source?.deadlineSeconds
            grpc.useTLS = source?.useTLS ?? false
            grpc.authorityOverride = source?.authorityOverride
            copy.grpcConfiguration = grpc
            modelContext.insert(grpc)
        }

        for parameter in request.parameters.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            let param = RequestParameterRecord(
                kind: parameter.kind,
                key: parameter.key,
                value: parameter.value,
                isEnabled: parameter.isEnabled,
                sortIndex: parameter.sortIndex,
                request: copy
            )
            modelContext.insert(param)
        }
        commandCenter.selectedRequestID = copy.id
        onSelectRequest(copy)
        try? modelContext.save()
    }

    private func delete(_ project: ProjectRecord) {
        if commandCenter.selectedProjectID == project.id {
            commandCenter.selectedProjectID = nil
            commandCenter.selectedRequestID = nil
        }
        modelContext.delete(project)
        try? modelContext.save()
    }

    private func delete(_ request: RequestRecord) {
        if commandCenter.selectedRequestID == request.id {
            commandCenter.selectedRequestID = nil
        }
        modelContext.delete(request)
        try? modelContext.save()
    }

    private func reorderProjects(from source: IndexSet, to destination: Int) {
        var ordered = projects
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, project) in ordered.enumerated() {
            project.sortIndex = Double(index)
        }
        try? modelContext.save()
    }

    private func reorderRequests(in project: ProjectRecord, from source: IndexSet, to destination: Int) {
        var ordered = project.requests.sorted { $0.sortIndex < $1.sortIndex }
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, request) in ordered.enumerated() {
            request.sortIndex = Double(index)
        }
        try? modelContext.save()
    }

    private func ensureRefreshCoordinator() async {
        if definitionRefreshCoordinator != nil { return }
        do {
            let store = try SchemaArtifactStore()
            let coordinator = DefinitionRefreshCoordinator(artifactStore: store)
            await coordinator.register(GraphQLDefinitionLoader())
            await coordinator.register(ProtobufDefinitionLoader())
            definitionRefreshCoordinator = coordinator
        } catch {
            definitionRefreshCoordinator = nil
        }
    }

    private func refreshDefinition(_ definition: APIDefinitionRecord) async {
        await ensureRefreshCoordinator()
        guard let coordinator = definitionRefreshCoordinator else {
            definition.status = .unavailable
            definition.lastErrorMessage = "Unable to initialize schema artifact store."
            try? modelContext.save()
            return
        }

        definition.status = .loading
        definition.lastAttemptAt = .now
        definition.updatedAt = .now
        try? modelContext.save()

        do {
            let result = try await coordinator.refresh(
                sourceID: definition.id,
                kind: definition.kind,
                configData: definition.configJSON
            )
            definition.activeFingerprint = result.fingerprint
            definition.activeSnapshotID = result.snapshotID
            definition.lastSuccessfulRefreshAt = .now
            definition.status = .ready
            definition.lastErrorMessage = nil
            definition.updatedAt = .now
            try? modelContext.save()
        } catch {
            if definition.activeFingerprint != nil {
                definition.status = .staleWithError
            } else {
                definition.status = .unavailable
            }
            definition.lastErrorMessage = (error as? DefinitionRefreshError)?.message ?? error.localizedDescription
            definition.updatedAt = .now
            try? modelContext.save()
        }
    }
}

private struct RenameNameSheet: View {
    let title: String
    @Binding var name: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFieldFocused)
                .onSubmit(onConfirm)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            nameFieldFocused = true
        }
    }
}
