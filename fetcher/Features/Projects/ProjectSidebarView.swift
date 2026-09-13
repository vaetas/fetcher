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
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { commandCenter.expandedProjectIDs.contains(project.id) },
                            set: { expanded in
                                if expanded {
                                    commandCenter.expandedProjectIDs.insert(project.id)
                                } else {
                                    commandCenter.expandedProjectIDs.remove(project.id)
                                }
                            }
                        )
                    ) {
                        ForEach(filteredRequests(for: project), id: \.id) { request in
                            requestRow(request)
                                .tag(request.id)
                                .contextMenu {
                                    Button("Duplicate") { duplicate(request) }
                                    Button("Rename") {
                                        beginRequestRename(request)
                                    }
                                    Divider()
                                    Button("Delete", role: .destructive) {
                                        confirmDeleteRequest = request
                                    }
                                }
                        }
                        .onMove { indices, newOffset in
                            reorderRequests(in: project, from: indices, to: newOffset)
                        }
                    } label: {
                        projectLabel(project)
                    }
                    .contextMenu {
                        Button("New Request") {
                            commandCenter.selectedProjectID = project.id
                            createRequest(in: project)
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
    }

    private var filteredProjects: [ProjectRecord] {
        let query = commandCenter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projects }
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(query)
                || filteredRequests(for: project).isEmpty == false
        }
    }

    private func filteredRequests(for project: ProjectRecord) -> [RequestRecord] {
        let requests = project.requests.sorted { $0.sortIndex < $1.sortIndex }
        let query = commandCenter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return requests }
        return requests.filter { request in
            request.name.localizedCaseInsensitiveContains(query)
                || (request.restConfiguration?.endpoint.localizedCaseInsensitiveContains(query) ?? false)
                || (request.restConfiguration?.method.localizedCaseInsensitiveContains(query) ?? false)
                || project.name.localizedCaseInsensitiveContains(query)
        }
    }

    @ViewBuilder
    private func projectLabel(_ project: ProjectRecord) -> some View {
        if renamingProjectID == project.id {
            TextField("Project name", text: $draftName)
                .textFieldStyle(.plain)
                .focused($renameFieldFocused)
                .onSubmit { commitProjectRename() }
                .onExitCommand { cancelProjectRename() }
        } else {
            Label(project.name, systemImage: "folder")
                .onTapGesture(count: 2) {
                    beginProjectRename(project)
                }
        }
    }

    @ViewBuilder
    private func requestRow(_ request: RequestRecord) -> some View {
        HStack(spacing: 8) {
            MethodBadge(method: request.restConfiguration?.method ?? "GET")
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(request.name)
                    .lineLimit(1)
                if let endpoint = request.restConfiguration?.endpoint, !endpoint.isEmpty {
                    Text(endpoint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            commandCenter.selectedRequestID = request.id
            commandCenter.selectedProjectID = request.project?.id
            onSelectRequest(request)
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            beginRequestRename(request)
        })
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
        createRequest(in: project)
        try? modelContext.save()
    }

    func createRequest(in project: ProjectRecord? = nil) {
        let target = project ?? projects.first(where: { $0.id == commandCenter.selectedProjectID }) ?? projects.first
        guard let target else {
            createProject()
            return
        }
        let request = RequestRecord(
            name: RequestRecord.defaultName,
            sortIndex: (target.requests.map(\.sortIndex).max() ?? 0) + 1,
            project: target
        )
        let rest = RESTRequestRecord(requestID: request.id)
        let auth = RequestAuthRecord(requestID: request.id)
        request.restConfiguration = rest
        request.auth = auth
        modelContext.insert(request)
        modelContext.insert(rest)
        modelContext.insert(auth)
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
            sortIndex: (project.requests.map(\.sortIndex).max() ?? 0) + 1,
            project: project
        )
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
        let authSource = request.auth
        let auth = RequestAuthRecord(
            requestID: copy.id,
            authType: authSource?.authKind ?? .none,
            nonSecretJSON: authSource?.nonSecretJSON ?? Data("{}".utf8),
            secretReferenceIDs: authSource?.secretReferenceIDs ?? []
        )
        copy.restConfiguration = rest
        copy.auth = auth
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
        modelContext.insert(copy)
        modelContext.insert(rest)
        modelContext.insert(auth)
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
