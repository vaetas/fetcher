import Foundation
import SwiftData

@Model
final class RequestParameterRecord {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var key: String
    var value: String
    var isEnabled: Bool
    var sortIndex: Double

    var request: RequestRecord?

    init(
        id: UUID = UUID(),
        kind: ParameterKind,
        key: String = "",
        value: String = "",
        isEnabled: Bool = true,
        sortIndex: Double = Date().timeIntervalSince1970,
        request: RequestRecord? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.key = key
        self.value = value
        self.isEnabled = isEnabled
        self.sortIndex = sortIndex
        self.request = request
    }

    var kind: ParameterKind {
        get { ParameterKind(rawValue: kindRaw) ?? .query }
        set { kindRaw = newValue.rawValue }
    }
}
