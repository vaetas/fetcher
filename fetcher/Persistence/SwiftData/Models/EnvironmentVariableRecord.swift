import Foundation
import SwiftData

@Model
final class EnvironmentVariableRecord {
    @Attribute(.unique) var id: UUID
    var key: String
    var value: String?
    var secretReferenceID: UUID?
    var isSecret: Bool
    var isEnabled: Bool
    var sortIndex: Double

    var environment: EnvironmentRecord?

    init(
        id: UUID = UUID(),
        key: String,
        value: String? = "",
        secretReferenceID: UUID? = nil,
        isSecret: Bool = false,
        isEnabled: Bool = true,
        sortIndex: Double = Date().timeIntervalSince1970,
        environment: EnvironmentRecord? = nil
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.secretReferenceID = secretReferenceID
        self.isSecret = isSecret
        self.isEnabled = isEnabled
        self.sortIndex = sortIndex
        self.environment = environment
    }
}
