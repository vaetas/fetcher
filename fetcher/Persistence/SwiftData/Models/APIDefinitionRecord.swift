import Foundation
import SwiftData

@Model
final class APIDefinitionRecord {
    @Attribute(.unique) var id: UUID
    var projectID: UUID
    var name: String
    var kindRawValue: String
    var sourceKindRawValue: String
    var configJSON: Data
    var activeSnapshotID: UUID?
    var activeFingerprint: String?
    var lastSuccessfulRefreshAt: Date?
    var lastAttemptAt: Date?
    var statusRawValue: String
    var lastErrorMessage: String?
    var createdAt: Date
    var updatedAt: Date
    var sortIndex: Double

    var project: ProjectRecord?

    init(
        id: UUID = UUID(),
        projectID: UUID,
        name: String,
        kind: APIDefinitionKind,
        sourceKindRawValue: String,
        configJSON: Data,
        sortIndex: Double = Date().timeIntervalSince1970,
        project: ProjectRecord? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.name = name
        self.kindRawValue = kind.rawValue
        self.sourceKindRawValue = sourceKindRawValue
        self.configJSON = configJSON
        self.activeSnapshotID = nil
        self.activeFingerprint = nil
        self.lastSuccessfulRefreshAt = nil
        self.lastAttemptAt = nil
        self.statusRawValue = DefinitionStatus.neverLoaded.rawValue
        self.lastErrorMessage = nil
        self.createdAt = .now
        self.updatedAt = .now
        self.sortIndex = sortIndex
        self.project = project
    }

    var kind: APIDefinitionKind {
        get { APIDefinitionKind(rawValue: kindRawValue) ?? .graphql }
        set { kindRawValue = newValue.rawValue }
    }

    var status: DefinitionStatus {
        get { DefinitionStatus(rawValue: statusRawValue) ?? .neverLoaded }
        set { statusRawValue = newValue.rawValue }
    }

    var sourceID: DefinitionSourceID {
        DefinitionSourceID(rawValue: id)
    }
}
