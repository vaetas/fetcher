import Foundation

final class RequestExecutionHandle: @unchecked Sendable {
    let id: UUID
    private let onCancel: @Sendable () -> Void

    init(id: UUID = UUID(), onCancel: @escaping @Sendable () -> Void) {
        self.id = id
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel()
    }
}

protocol APIRequestExecutor: Sendable {
    var kind: APIProtocolKind { get }

    func execute(
        draft: RESTRequestDraft,
        context: ExecutionContext
    ) async throws -> APIExecutionResult
}

actor RequestExecutorRegistry {
    private var executors: [APIProtocolKind: any APIRequestExecutor]

    init(executors: [APIProtocolKind: any APIRequestExecutor] = [:]) {
        self.executors = executors
    }

    func register(_ executor: any APIRequestExecutor) {
        executors[executor.kind] = executor
    }

    func executor(for kind: APIProtocolKind) -> (any APIRequestExecutor)? {
        executors[kind]
    }
}

struct RESTRequestExecutor: APIRequestExecutor {
    let kind: APIProtocolKind = .rest
    private let builder: RESTRequestBuilder
    private let sessionManager: RESTSessionManager
    private let maxResponseBytes: Int

    init(
        builder: RESTRequestBuilder = RESTRequestBuilder(),
        sessionManager: RESTSessionManager = RESTSessionManager(),
        maxResponseBytes: Int = 50 * 1024 * 1024
    ) {
        self.builder = builder
        self.sessionManager = sessionManager
        self.maxResponseBytes = maxResponseBytes
    }

    func execute(draft: RESTRequestDraft, context: ExecutionContext) async throws -> APIExecutionResult {
        let startedAt = Date()
        let (resolved, _, _) = try await builder.build(draft)

        let key = RESTSessionManager.SessionKey(
            projectID: context.projectID,
            redirectPolicy: resolved.redirectPolicy,
            tlsPolicy: resolved.tlsPolicy
        )
        let (session, delegate) = await sessionManager.session(for: key)

        var request = URLRequest(url: resolved.url)
        request.httpMethod = resolved.method
        request.timeoutInterval = resolved.timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        for (name, value) in resolved.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = resolved.body

        do {
            let (data, response) = try await session.data(for: request)
            let finishedAt = Date()
            let http = response as? HTTPURLResponse

            var metrics = RequestMetricsCollector.collect(from: delegate.latestMetrics)
            if metrics.totalDuration == nil {
                metrics.totalDuration = finishedAt.timeIntervalSince(startedAt)
            }
            let redirects = delegate.latestRedirects

            if data.count > maxResponseBytes {
                throw RESTExecutionError.responseTooLarge(data.count)
            }

            let artifact = RESTResponseArtifact(
                id: UUID(),
                requestID: draft.requestID,
                startedAt: startedAt,
                finishedAt: finishedAt,
                originalURL: resolved.url,
                finalURL: http?.url ?? response.url,
                statusCode: http?.statusCode,
                headers: headerPairs(from: http),
                body: data,
                mimeType: http?.mimeType,
                textEncodingName: http?.textEncodingName,
                expectedContentLength: http?.expectedContentLength,
                metrics: metrics,
                redirects: redirects,
                error: nil
            )
            return .rest(artifact)
        } catch let error as RESTExecutionError {
            throw error
        } catch let urlError as URLError {
            throw mapURLError(urlError)
        } catch is CancellationError {
            throw RESTExecutionError.cancelled
        } catch {
            throw RESTExecutionError.transport(.unknown(error.localizedDescription))
        }
    }

    func preview(draft: RESTRequestDraft) async throws -> PreparedRequestPreview {
        let (_, preview, _) = try await builder.build(draft)
        return preview
    }

    private func headerPairs(from response: HTTPURLResponse?) -> [(String, String)] {
        guard let response else { return [] }
        return response.allHeaderFields.compactMap { key, value in
            guard let name = key as? String else { return nil }
            return (name, String(describing: value))
        }
        .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    private func mapURLError(_ error: URLError) -> RESTExecutionError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        case .cannotFindHost, .dnsLookupFailed:
            return .transport(.dnsFailure(error.localizedDescription))
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected:
            return .tls(error.localizedDescription)
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return .transport(.connectionFailure(error.localizedDescription))
        default:
            return .transport(.unknown(error.localizedDescription))
        }
    }
}
