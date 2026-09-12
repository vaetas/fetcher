import Foundation
import SwiftData

@Model
final class RESTRequestRecord {
    @Attribute(.unique) var requestID: UUID
    var method: String
    var endpoint: String
    var bodyModeRaw: String
    var bodyText: String
    var timeoutSeconds: Double?
    var redirectPolicyRaw: String
    var cookiePolicyRaw: String
    var cachePolicyRaw: String
    var tlsPolicyRaw: String

    var request: RequestRecord?

    init(
        requestID: UUID,
        method: String = "GET",
        endpoint: String = "/",
        bodyMode: RESTBodyMode = .none,
        bodyText: String = "",
        timeoutSeconds: Double? = nil,
        redirectPolicy: RedirectPolicy = .follow
    ) {
        self.requestID = requestID
        self.method = method
        self.endpoint = endpoint
        self.bodyModeRaw = bodyMode.rawValue
        self.bodyText = bodyText
        self.timeoutSeconds = timeoutSeconds
        self.redirectPolicyRaw = redirectPolicy.rawValue
        self.cookiePolicyRaw = CookiePolicy.isolatedEphemeral.rawValue
        self.cachePolicyRaw = CachePolicy.ignoreLocalCache.rawValue
        self.tlsPolicyRaw = TLSPolicy.systemDefault.rawValue
    }

    var bodyMode: RESTBodyMode {
        get { RESTBodyMode(rawValue: bodyModeRaw) ?? .none }
        set { bodyModeRaw = newValue.rawValue }
    }

    var redirectPolicy: RedirectPolicy {
        get { RedirectPolicy(rawValue: redirectPolicyRaw) ?? .follow }
        set { redirectPolicyRaw = newValue.rawValue }
    }
}
