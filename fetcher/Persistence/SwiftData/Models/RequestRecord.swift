import Foundation
import SwiftData

@Model
final class RequestRecord {
    static let defaultName = "New Request"

    static func displayName(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == defaultName {
            return defaultName
        }
        return trimmed
    }

    @Attribute(.unique) var id: UUID
    var name: String
    var protocolKindRaw: String
    var createdAt: Date
    var updatedAt: Date
    var sortIndex: Double

    var project: ProjectRecord?

    @Relationship(deleteRule: .cascade, inverse: \RESTRequestRecord.request)
    var restConfiguration: RESTRequestRecord?

    @Relationship(deleteRule: .cascade, inverse: \GraphQLRequestRecord.request)
    var graphqlConfiguration: GraphQLRequestRecord?

    @Relationship(deleteRule: .cascade, inverse: \GRPCRequestRecord.request)
    var grpcConfiguration: GRPCRequestRecord?

    @Relationship(deleteRule: .cascade, inverse: \RequestParameterRecord.request)
    var parameters: [RequestParameterRecord]

    @Relationship(deleteRule: .cascade, inverse: \RequestAuthRecord.request)
    var auth: RequestAuthRecord?

    init(
        id: UUID = UUID(),
        name: String,
        protocolKind: APIProtocolKind = .rest,
        sortIndex: Double = Date().timeIntervalSince1970,
        project: ProjectRecord? = nil
    ) {
        self.id = id
        self.name = name
        self.protocolKindRaw = protocolKind.rawValue
        self.createdAt = .now
        self.updatedAt = .now
        self.sortIndex = sortIndex
        self.project = project
        self.parameters = []
    }

    var protocolKind: APIProtocolKind {
        get { APIProtocolKind(rawValue: protocolKindRaw) ?? .rest }
        set { protocolKindRaw = newValue.rawValue }
    }

    var projectID: UUID? {
        project?.id
    }
}
