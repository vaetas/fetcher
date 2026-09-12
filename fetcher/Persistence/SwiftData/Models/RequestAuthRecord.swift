import Foundation
import SwiftData

@Model
final class RequestAuthRecord {
    @Attribute(.unique) var requestID: UUID
    var authTypeRaw: String
    var nonSecretJSON: Data
    var secretReferenceIDs: [UUID]

    var request: RequestRecord?

    init(
        requestID: UUID,
        authType: AuthKind = .none,
        nonSecretJSON: Data = Data("{}".utf8),
        secretReferenceIDs: [UUID] = []
    ) {
        self.requestID = requestID
        self.authTypeRaw = authType.rawValue
        self.nonSecretJSON = nonSecretJSON
        self.secretReferenceIDs = secretReferenceIDs
    }

    var authKind: AuthKind {
        get { AuthKind(rawValue: authTypeRaw) ?? .none }
        set { authTypeRaw = newValue.rawValue }
    }
}
