import SwiftData
import SwiftUI

struct ContentRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ProjectRecord.sortIndex) private var projects: [ProjectRecord]
    @Bindable var commandCenter: AppCommandCenter
    @Bindable var workspace: RequestWorkspaceModel
    let secretStore: any SecretStore

    @State private var showProjectSettings = false

    var body: some View {
        Group {
            if let request = selectedRequest {
                observedRoot(request: request)
            } else {
                rootNavigationSplitView
                    .navigationTitle(RequestRecord.defaultName)
            }
        }
        .frame(minWidth: 960, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .onAppear {
            commandCenter.workspace = workspace
            commandCenter.onNewProject = { createProject() }
            commandCenter.onNewRequest = { createRequest(kind: .rest) }
            commandCenter.onNewGraphQLRequest = { createRequest(kind: .graphql) }
            commandCenter.onNewGRPCRequest = { createRequest(kind: .grpc) }
            commandCenter.onDuplicateRequest = { duplicateRequest() }
            restoreSelectionIfNeeded()
        }
        .sheet(isPresented: $showProjectSettings) {
            if let project = selectedProject {
                NavigationStack {
                    ProjectSettingsView(project: project, secretStore: secretStore)
                        .navigationTitle("Project Settings")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showProjectSettings = false }
                            }
                        }
                }
                .presentationSizing(.form)
                .frame(minWidth: 640, minHeight: 480)
            }
        }
    }

    @ViewBuilder
    private func observedRoot(request: RequestRecord) -> some View {
        @Bindable var request = request
        rootNavigationSplitView
            .navigationTitle(RequestRecord.displayName(for: request.name))
    }

    private var rootNavigationSplitView: some View {
        NavigationSplitView {
            ProjectSidebarView(
                commandCenter: commandCenter,
                onSelectRequest: { _ in },
                onOpenProjectSettings: { project in
                    commandCenter.selectedProjectID = project.id
                    showProjectSettings = true
                }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } detail: {
            RequestWorkspaceView(
                commandCenter: commandCenter,
                workspace: workspace,
                request: selectedRequest,
                secretStore: secretStore
            )
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        createRequest(kind: .rest)
                    } label: {
                        Label("New Request", systemImage: "plus")
                    }
                    .help("New REST Request")

                    Menu {
                        Button("REST") { createRequest(kind: .rest) }
                        Button("GraphQL") { createRequest(kind: .graphql) }
                        Button("gRPC") { createRequest(kind: .grpc) }
                    } label: {
                        Label("New Protocol Request", systemImage: "plus.square.on.square")
                    }
                    .help("Create request by protocol")

                    if let project = selectedProject {
                        Picker(
                            "Environment",
                            selection: Binding(
                                get: { project.selectedEnvironmentID },
                                set: {
                                    project.selectedEnvironmentID = $0
                                    try? modelContext.save()
                                }
                            )
                        ) {
                            ForEach(project.environments.sorted(by: { $0.sortIndex < $1.sortIndex }), id: \.id) { environment in
                                Text(environment.name).tag(Optional(environment.id))
                            }
                        }
                        .frame(maxWidth: 180)
                        .help("Active environment")
                    }

                    Button {
                        if workspace.executionState == .running {
                            commandCenter.perform(.cancelRequest)
                        } else {
                            commandCenter.perform(.sendRequest)
                        }
                    } label: {
                        Label(
                            workspace.executionState == .running ? "Stop" : "Send",
                            systemImage: workspace.executionState == .running ? "stop.fill" : "paperplane.fill"
                        )
                    }
                    .help(workspace.executionState == .running ? "Stop" : "Send")
                    .disabled(selectedRequest == nil)

                    Button {
                        showProjectSettings = true
                    } label: {
                        Label("Project Settings", systemImage: "folder.badge.gearshape")
                    }
                    .disabled(selectedProject == nil)
                    .help("Project Settings")
                }
            }
            .inspector(isPresented: $commandCenter.isInspectorPresented) {
                RequestInspectorView(request: selectedRequest, preview: workspace.preview)
                    .inspectorColumnWidth(min: 240, ideal: 300, max: 420)
            }
        }
    }

    private var selectedRequest: RequestRecord? {
        guard let id = commandCenter.selectedRequestID else { return nil }
        return projects.flatMap(\.requests).first(where: { $0.id == id })
    }

    private var selectedProject: ProjectRecord? {
        if let id = commandCenter.selectedProjectID {
            return projects.first(where: { $0.id == id })
        }
        return selectedRequest?.project
    }

    private func restoreSelectionIfNeeded() {
        if commandCenter.selectedRequestID == nil {
            if let first = projects.first {
                commandCenter.selectedProjectID = first.id
                commandCenter.expandedProjectIDs.insert(first.id)
                if let request = first.requests.sorted(by: { $0.sortIndex < $1.sortIndex }).first {
                    commandCenter.selectedRequestID = request.id
                }
            }
        }
    }

    private func createProject() {
        let project = ProjectRecord(name: "New Project", sortIndex: (projects.map(\.sortIndex).max() ?? 0) + 1)
        let environment = EnvironmentRecord(name: "Development", baseURL: "http://localhost:8787", project: project)
        project.environments = [environment]
        project.selectedEnvironmentID = environment.id
        modelContext.insert(project)
        modelContext.insert(environment)
        commandCenter.selectedProjectID = project.id
        commandCenter.expandedProjectIDs.insert(project.id)
        createRequest(in: project)
        try? modelContext.save()
    }

    private func createRequest(in project: ProjectRecord? = nil, kind: APIProtocolKind = .rest) {
        let target = project ?? selectedProject ?? projects.first
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
            let rest = RESTRequestRecord(requestID: request.id, endpoint: "/api/books")
            request.restConfiguration = rest
            modelContext.insert(rest)
        case .graphql:
            let endpoint = target.baseURL.isEmpty ? "http://localhost:4000/graphql" : "\(target.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/graphql"
            let graphql = GraphQLRequestRecord(requestID: request.id, endpoint: endpoint)
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
        try? modelContext.save()
    }

    private func duplicateRequest() {
        guard let request = selectedRequest, let project = request.project else { return }
        let copy = RequestRecord(
            name: "\(request.name) Copy",
            protocolKind: request.protocolKind,
            sortIndex: (project.requests.map(\.sortIndex).max() ?? 0) + 1,
            project: project
        )
        let auth = RequestAuthRecord(
            requestID: copy.id,
            authType: request.auth?.authKind ?? .none,
            nonSecretJSON: request.auth?.nonSecretJSON ?? Data("{}".utf8),
            secretReferenceIDs: request.auth?.secretReferenceIDs ?? []
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
            copy.grpcConfiguration = grpc
            modelContext.insert(grpc)
        }

        for parameter in request.parameters.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            modelContext.insert(
                RequestParameterRecord(
                    kind: parameter.kind,
                    key: parameter.key,
                    value: parameter.value,
                    isEnabled: parameter.isEnabled,
                    sortIndex: parameter.sortIndex,
                    request: copy
                )
            )
        }
        commandCenter.selectedRequestID = copy.id
        try? modelContext.save()
    }
}
