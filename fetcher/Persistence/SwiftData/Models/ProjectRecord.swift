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
        self.defaultTimeoutSeconds = 30
        self.defaultRedirectPolicyRaw = RedirectPolicy.follow.rawValue
        self.defaultAuthTypeRaw = AuthKind.none.rawValue
        self.defaultAuthNonSecretJSON = Data("{}".utf8)
        self.defaultAuthSecretReferenceIDs = []
        self.defaultHeadersJSON = Data("[]".utf8)
        self.requests = []
        self.environments = []
    }

    var defaultRedirectPolicy: RedirectPolicy {
        get { RedirectPolicy(rawValue: defaultRedirectPolicyRaw) ?? .follow }
        set { defaultRedirectPolicyRaw = newValue.rawValue }
    }

    var defaultAuthKind: AuthKind {
        get { AuthKind(rawValue: defaultAuthTypeRaw) ?? .none }
        set { defaultAuthTypeRaw = newValue.rawValue }
    }
}
