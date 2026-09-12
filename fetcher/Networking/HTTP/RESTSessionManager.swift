import Foundation

actor RESTSessionManager {
    struct SessionKey: Hashable, Sendable {
        let projectID: UUID
        let redirectPolicy: RedirectPolicy
        let tlsPolicy: TLSPolicy
    }

    private var sessions: [SessionKey: URLSession] = [:]
    private var delegates: [SessionKey: RESTURLSessionDelegate] = [:]

    func session(for key: SessionKey) -> (URLSession, RESTURLSessionDelegate) {
        if let existing = sessions[key], let delegate = delegates[key] {
            return (existing, delegate)
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = true
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60

        let delegate = RESTURLSessionDelegate(followRedirects: key.redirectPolicy == .follow)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        sessions[key] = session
        delegates[key] = delegate
        return (session, delegate)
    }

    func invalidate(projectID: UUID) {
        let keys = sessions.keys.filter { $0.projectID == projectID }
        for key in keys {
            sessions[key]?.invalidateAndCancel()
            sessions.removeValue(forKey: key)
            delegates.removeValue(forKey: key)
        }
    }

    func invalidateAll() {
        for session in sessions.values {
            session.invalidateAndCancel()
        }
        sessions.removeAll()
        delegates.removeAll()
    }
}
