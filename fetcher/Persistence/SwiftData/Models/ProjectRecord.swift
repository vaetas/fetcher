import Foundation
import SwiftData

@Model
final class ProjectRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var sortIndex: Double
    var baseURL: String
    var selectedEnvironmentID: UUID?
    /// The GraphQL schema shared by every GraphQL request in this project.
    /// Individual request references remain as a legacy fallback for projects
    /// created before the project-level setting was introduced.
    var graphQLDefinitionSourceID: UUID?
    var defaultTimeoutSeconds: Double
    var defaultRedirectPolicyRaw: String
    var defaultAuthTypeRaw: String
    var defaultAuthNonSecretJSON: Data
    var defaultAuthSecretReferenceIDs: [UUID]
    var defaultHeadersJSON: Data

    @Relationship(deleteRule: .cascade, inverse: \RequestRecord.project)
    var requests: [RequestRecord]

    @Relationship(deleteRule: .cascade, inverse: \EnvironmentRecord.project)
    var environments: [EnvironmentRecord]

    @Relationship(deleteRule: .cascade, inverse: \APIDefinitionRecord.project)
    var apiDefinitions: [APIDefinitionRecord]

    init(
        id: UUID = UUID(),
        name: String,
        sortIndex: Double = Date().timeIntervalSince1970,
        baseURL: String = ""
    ) {
        self.id = id
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
        self.sortIndex = sortIndex
        self.baseURL = baseURL
        self.selectedEnvironmentID = nil
        self.graphQLDefinitionSourceID = nil
        self.defaultTimeoutSeconds = 30
        self.defaultRedirectPolicyRaw = RedirectPolicy.follow.rawValue
        self.defaultAuthTypeRaw = AuthKind.none.rawValue
        self.defaultAuthNonSecretJSON = Data("{}".utf8)
        self.defaultAuthSecretReferenceIDs = []
        self.defaultHeadersJSON = Data("[]".utf8)
        self.requests = []
        self.environments = []
        self.apiDefinitions = []
    }

    var defaultRedirectPolicy: RedirectPolicy {
        get { RedirectPolicy(rawValue: defaultRedirectPolicyRaw) ?? .follow }
        set { defaultRedirectPolicyRaw = newValue.rawValue }
    }

    var defaultAuthKind: AuthKind {
        get { AuthKind(rawValue: defaultAuthTypeRaw) ?? .none }
        set { defaultAuthTypeRaw = newValue.rawValue }
    }

    var graphQLDefinition: APIDefinitionRecord? {
        guard let graphQLDefinitionSourceID else { return nil }
        return apiDefinitions.first { definition in
            definition.id == graphQLDefinitionSourceID && definition.kind == .graphql
        }
    }

    func setSharedGraphQLDefinition(_ definitionID: UUID?) {
        graphQLDefinitionSourceID = definitionID
        for request in requests where request.protocolKind == .graphql {
            request.graphqlConfiguration?.definitionSourceID = definitionID
            request.updatedAt = .now
        }
        updatedAt = .now
    }
}
