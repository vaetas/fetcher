import SwiftData
import SwiftUI

struct APIDefinitionsSidebarSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectRecord
    @Binding var selectedDefinitionID: UUID?
    var onRefresh: (APIDefinitionRecord) -> Void
    var onAdd: () -> Void
    var onUseForProjectGraphQL: (APIDefinitionRecord) -> Void

    private var sortedDefinitions: [APIDefinitionRecord] {
        project.apiDefinitions.sorted { $0.sortIndex < $1.sortIndex }
    }

    var body: some View {
        Section("API Definitions") {
            ForEach(sortedDefinitions, id: \.id) { definition in
                definitionRow(definition)
                    .tag(definition.id)
                    .contextMenu {
                        Button("Refresh") {
                            onRefresh(definition)
                        }
                        if definition.kind == .graphql {
                            Button("Use for Project GraphQL Requests") {
                                onUseForProjectGraphQL(definition)
                            }
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            delete(definition)
                        }
                    }
            }

            Button(action: onAdd) {
                Label("Add API Definition", systemImage: "plus")
            }
        }
    }

    private func definitionRow(_ definition: APIDefinitionRecord) -> some View {
        HStack(spacing: 8) {
            DefinitionStatusIndicator(status: definition.status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(definition.name)
                    if definition.id == project.graphQLDefinitionSourceID {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Shared project GraphQL schema")
                    }
                }
                Text(definition.kind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDefinitionID = definition.id
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(definition.name), \(definition.kind.displayName), \(definition.status.displayName)")
    }

    private func delete(_ definition: APIDefinitionRecord) {
        if selectedDefinitionID == definition.id {
            selectedDefinitionID = nil
        }
        if project.graphQLDefinitionSourceID == definition.id {
            project.setSharedGraphQLDefinition(nil)
        }
        modelContext.delete(definition)
        project.updatedAt = .now
        try? modelContext.save()
    }
}

struct DefinitionStatusIndicator: View {
    let status: DefinitionStatus

    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(color)
            .font(.caption)
            .accessibilityLabel(status.displayName)
    }

    private var iconName: String {
        switch status {
        case .neverLoaded: "circle.dashed"
        case .loading: "arrow.triangle.2.circlepath"
        case .ready: "checkmark.circle.fill"
        case .staleWithError: "exclamationmark.triangle.fill"
        case .unavailable: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch status {
        case .neverLoaded: .secondary
        case .loading: .orange
        case .ready: .green
        case .staleWithError: .orange
        case .unavailable: .red
        }
    }
}
