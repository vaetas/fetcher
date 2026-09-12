import Foundation
import SwiftData

@Model
final class EnvironmentRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var baseURL: String
    var sortIndex: Double

    var project: ProjectRecord?

    @Relationship(deleteRule: .cascade, inverse: \EnvironmentVariableRecord.environment)
    var variables: [EnvironmentVariableRecord]

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String = "",
        sortIndex: Double = Date().timeIntervalSince1970,
        project: ProjectRecord? = nil
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.sortIndex = sortIndex
        self.project = project
        self.variables = []
    }
}
