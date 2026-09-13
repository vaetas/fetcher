import Foundation

struct GraphQLNamedTypeID: Hashable, Codable, Sendable {
    let name: String
}

struct GraphQLArgumentDescriptor: Sendable, Hashable {
    let name: String
    let typeName: String
    let defaultValue: String?
    let description: String?
    let isDeprecated: Bool
    let deprecationReason: String?
}

struct GraphQLFieldDescriptor: Sendable, Hashable {
    let name: String
    let typeName: String
    let description: String?
    let arguments: [GraphQLArgumentDescriptor]
    let isDeprecated: Bool
    let deprecationReason: String?
}

struct GraphQLEnumValueDescriptor: Sendable, Hashable {
    let name: String
    let description: String?
    let isDeprecated: Bool
    let deprecationReason: String?
}

struct GraphQLInputFieldDescriptor: Sendable, Hashable {
    let name: String
    let typeName: String
    let description: String?
    let defaultValue: String?
    let isDeprecated: Bool
}

struct GraphQLTypeDescriptor: Sendable, Hashable {
    enum Kind: String, Sendable {
        case scalar
        case object
        case interface
        case union
        case enumType = "enum"
        case inputObject
    }

    let name: String
    let kind: Kind
    let description: String?
    let fields: [GraphQLFieldDescriptor]
    let inputFields: [GraphQLInputFieldDescriptor]
    let enumValues: [GraphQLEnumValueDescriptor]
    let interfaces: [String]
    let possibleTypes: [String]
}

struct GraphQLDirectiveDescriptor: Sendable, Hashable {
    let name: String
    let description: String?
    let locations: [String]
    let arguments: [GraphQLArgumentDescriptor]
}

struct GraphQLSchemaSnapshot: Sendable {
    let id: SchemaSnapshotID
    let queryType: GraphQLNamedTypeID?
    let mutationType: GraphQLNamedTypeID?
    let subscriptionType: GraphQLNamedTypeID?
    let typesByName: [String: GraphQLTypeDescriptor]
    let directivesByName: [String: GraphQLDirectiveDescriptor]

    func type(named name: String) -> GraphQLTypeDescriptor? {
        typesByName[name]
    }

    var rootQueryFields: [GraphQLFieldDescriptor] {
        guard let queryType, let type = typesByName[queryType.name] else { return [] }
        return type.fields
    }
}

struct GraphQLOperationInfo: Sendable, Equatable {
    enum Kind: String, Sendable {
        case query
        case mutation
        case subscription
    }

    let kind: Kind
    let name: String?
    let variableDefinitions: [GraphQLVariableDefinition]
}

struct GraphQLVariableDefinition: Sendable, Equatable {
    let name: String
    let typeName: String
    let defaultValue: String?
}

struct GraphQLDocument: Sendable {
    let source: String
    let operations: [GraphQLOperationInfo]
    let fragmentNames: [String]
}

protocol GraphQLLanguageService: Sendable {
    func loadSDL(_ source: String) throws -> GraphQLSchemaSnapshot
    func loadIntrospectionJSON(_ data: Data) throws -> GraphQLSchemaSnapshot
    func parseDocument(_ source: String) throws -> GraphQLDocument
    func validate(document: GraphQLDocument, against schema: GraphQLSchemaSnapshot) -> [EditorDiagnostic]
    func completions(
        document: String,
        cursorUTF16Offset: Int,
        schema: GraphQLSchemaSnapshot
    ) -> [CompletionItem]
    func syntaxDiagnostics(in source: String) -> [EditorDiagnostic]
}

struct GraphQLLanguageServiceFactory {
    static func makeDefault() -> any GraphQLLanguageService {
        BuiltinGraphQLLanguageService()
    }
}
