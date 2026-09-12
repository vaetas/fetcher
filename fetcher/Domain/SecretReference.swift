import Foundation

struct SecretReference: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let label: String

    init(id: UUID = UUID(), label: String) {
        self.id = id
        self.label = label
    }
}
