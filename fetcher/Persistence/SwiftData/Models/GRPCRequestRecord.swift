import Foundation
import SwiftData

@Model
final class GRPCRequestRecord {
    @Attribute(.unique) var requestID: UUID
    var definitionSourceID: UUID?
    var target: String
    var serviceFullName: String
    var methodName: String
    var bodyJSON: String
    var outboundMessagesJSON: Data
    var deadlineSeconds: Double?
    var useTLS: Bool
    var authorityOverride: String?
    var compressionRaw: String?

    var request: RequestRecord?

    init(
        requestID: UUID,
        target: String = "localhost:50051",
        serviceFullName: String = "",
        methodName: String = "",
        bodyJSON: String = "{}"
    ) {
        self.requestID = requestID
        self.definitionSourceID = nil
        self.target = target
        self.serviceFullName = serviceFullName
        self.methodName = methodName
        self.bodyJSON = bodyJSON
        self.outboundMessagesJSON = Data("[]".utf8)
        self.deadlineSeconds = 30
        self.useTLS = false
        self.authorityOverride = nil
        self.compressionRaw = GRPCCompressionPreference.none.rawValue
    }

    var outboundMessages: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: outboundMessagesJSON)) ?? []
        }
        set {
            outboundMessagesJSON = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8)
        }
    }

    var tls: GRPCTLSConfiguration {
        get {
            GRPCTLSConfiguration(useTLS: useTLS, authorityOverride: authorityOverride)
        }
        set {
            useTLS = newValue.useTLS
            authorityOverride = newValue.authorityOverride
        }
    }
}
