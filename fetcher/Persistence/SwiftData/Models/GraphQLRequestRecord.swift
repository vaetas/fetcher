import Foundation
import SwiftData

@Model
final class GraphQLRequestRecord {
    @Attribute(.unique) var requestID: UUID
    var definitionSourceID: UUID?
    var endpoint: String
    var document: String
    var operationName: String?
    var variablesJSON: String
    var extensionsJSON: String?
    var methodPreferenceRaw: String
    var timeoutSeconds: Double?

    var request: RequestRecord?

    init(
        requestID: UUID,
        endpoint: String = "",
        document: String = "query {\n  \n}\n",
        variablesJSON: String = "{}",
        methodPreference: GraphQLHTTPMethodPreference = .post
    ) {
        self.requestID = requestID
        self.definitionSourceID = nil
        self.endpoint = endpoint
        self.document = document
        self.operationName = nil
        self.variablesJSON = variablesJSON
        self.extensionsJSON = nil
        self.methodPreferenceRaw = methodPreference.rawValue
        self.timeoutSeconds = nil
    }

    var methodPreference: GraphQLHTTPMethodPreference {
        get { GraphQLHTTPMethodPreference(rawValue: methodPreferenceRaw) ?? .post }
        set { methodPreferenceRaw = newValue.rawValue }
    }
}
