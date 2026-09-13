import SwiftUI

enum GraphQLSchemaOutlineItem: Hashable, Identifiable {
    case rootOperation(GraphQLOperationInfo.Kind)
    case rootField(GraphQLOperationInfo.Kind, String)
    case type(String)
    case directive(String)

    var id: String {
        switch self {
        case .rootOperation(let kind): "root-\(kind.rawValue)"
        case .rootField(let kind, let name): "root-\(kind.rawValue)-\(name)"
        case .type(let name): "type-\(name)"
        case .directive(let name): "directive-\(name)"
        }
    }
}

struct GraphQLSchemaBrowser: View {
    let schema: GraphQLSchemaSnapshot?
    @State private var selection: GraphQLSchemaOutlineItem?

    var body: some View {
        if schema == nil {
            EmptyStateView(
                title: "No Schema",
                message: "Attach and refresh a GraphQL API definition to browse query, mutation, subscription, types, and directives."
            )
        } else {
            NavigationSplitView {
                List(selection: $selection) {
                    if let schema {
                        if schema.queryType != nil {
                            Section("Query") {
                                outlineFields(for: .query, schema: schema)
                            }
                        }
                        if schema.mutationType != nil {
                            Section("Mutation") {
                                outlineFields(for: .mutation, schema: schema)
                            }
                        }
                        if schema.subscriptionType != nil {
                            Section("Subscription") {
                                outlineFields(for: .subscription, schema: schema)
                            }
                        }
                        Section("Types") {
                            ForEach(sortedTypes(schema), id: \.self) { name in
                                Label(name, systemImage: iconName(for: schema.typesByName[name]?.kind))
                                    .tag(GraphQLSchemaOutlineItem.type(name))
                            }
                        }
                        Section("Directives") {
                            ForEach(schema.directivesByName.keys.sorted(), id: \.self) { name in
                                Label(name, systemImage: "at")
                                    .tag(GraphQLSchemaOutlineItem.directive(name))
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240)
            } detail: {
                if let schema, let selection {
                    GraphQLSchemaDetailView(schema: schema, selection: selection)
                } else {
                    EmptyStateView(
                        title: "Schema Detail",
                        message: "Select a root field, type, or directive to inspect its definition."
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func outlineFields(for kind: GraphQLOperationInfo.Kind, schema: GraphQLSchemaSnapshot) -> some View {
        ForEach(rootFields(for: kind, schema: schema), id: \.name) { field in
            Label(field.name, systemImage: "circle.fill")
                .tag(GraphQLSchemaOutlineItem.rootField(kind, field.name))
        }
    }

    private func rootFields(for kind: GraphQLOperationInfo.Kind, schema: GraphQLSchemaSnapshot) -> [GraphQLFieldDescriptor] {
        let typeName: String?
        switch kind {
        case .query: typeName = schema.queryType?.name
        case .mutation: typeName = schema.mutationType?.name
        case .subscription: typeName = schema.subscriptionType?.name
        }
        guard let typeName, let type = schema.typesByName[typeName] else { return [] }
        return type.fields.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func sortedTypes(_ schema: GraphQLSchemaSnapshot) -> [String] {
        schema.typesByName.keys.sorted()
    }

    private func iconName(for kind: GraphQLTypeDescriptor.Kind?) -> String {
        switch kind {
        case .scalar: "number"
        case .object: "square.stack.3d.up"
        case .interface: "square.dashed"
        case .union: "arrow.triangle.branch"
        case .enumType: "list.bullet"
        case .inputObject: "rectangle.and.pencil.and.ellipsis"
        case nil: "questionmark"
        }
    }
}

private struct GraphQLSchemaDetailView: View {
    let schema: GraphQLSchemaSnapshot
    let selection: GraphQLSchemaOutlineItem

    var body: some View {
        ScrollView {
            Form {
                switch selection {
                case .rootOperation(let kind):
                    Section(kind.rawValue.capitalized) {
                        Text("Root \(kind.rawValue) type")
                            .foregroundStyle(.secondary)
                    }
                case .rootField(let kind, let name):
                    if let field = rootFields(for: kind).first(where: { $0.name == name }) {
                        fieldDetail(field)
                    }
                case .type(let name):
                    if let type = schema.typesByName[name] {
                        typeDetail(type)
                    }
                case .directive(let name):
                    if let directive = schema.directivesByName[name] {
                        directiveDetail(directive)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
    }

    private func rootFields(for kind: GraphQLOperationInfo.Kind) -> [GraphQLFieldDescriptor] {
        let typeName: String?
        switch kind {
        case .query: typeName = schema.queryType?.name
        case .mutation: typeName = schema.mutationType?.name
        case .subscription: typeName = schema.subscriptionType?.name
        }
        guard let typeName, let type = schema.typesByName[typeName] else { return [] }
        return type.fields
    }

    @ViewBuilder
    private func fieldDetail(_ field: GraphQLFieldDescriptor) -> some View {
        Section(field.name) {
            if let description = field.description {
                Text(description)
            }
            LabeledContent("Type", value: field.typeName)
            if field.isDeprecated {
                Text(field.deprecationReason ?? "Deprecated")
                    .foregroundStyle(.orange)
            }
        }
        if !field.arguments.isEmpty {
            Section("Arguments") {
                ForEach(field.arguments, id: \.name) { argument in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(argument.name).font(.headline)
                        Text(argument.typeName).font(.caption.monospaced()).foregroundStyle(.secondary)
                        if let description = argument.description {
                            Text(description)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func typeDetail(_ type: GraphQLTypeDescriptor) -> some View {
        Section(type.name) {
            LabeledContent("Kind", value: type.kind.rawValue)
            if let description = type.description {
                Text(description)
            }
        }
        if !type.fields.isEmpty {
            Section("Fields") {
                ForEach(type.fields, id: \.name) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(field.name): \(field.typeName)")
                            .font(.body.monospaced())
                        if let description = field.description {
                            Text(description).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        if !type.inputFields.isEmpty {
            Section("Input Fields") {
                ForEach(type.inputFields, id: \.name) { field in
                    Text("\(field.name): \(field.typeName)")
                        .font(.body.monospaced())
                }
            }
        }
        if !type.enumValues.isEmpty {
            Section("Enum Values") {
                ForEach(type.enumValues, id: \.name) { value in
                    Text(value.name)
                }
            }
        }
    }

    @ViewBuilder
    private func directiveDetail(_ directive: GraphQLDirectiveDescriptor) -> some View {
        Section(directive.name) {
            if let description = directive.description {
                Text(description)
            }
            LabeledContent("Locations", value: directive.locations.joined(separator: ", "))
        }
        if !directive.arguments.isEmpty {
            Section("Arguments") {
                ForEach(directive.arguments, id: \.name) { argument in
                    Text("\(argument.name): \(argument.typeName)")
                        .font(.body.monospaced())
                }
            }
        }
    }
}
