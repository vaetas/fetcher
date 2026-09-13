import Foundation

protocol GraphQLHTTPTransport: Sendable {
    func execute(
        request: GraphQLExecutionRequest,
        context: ExecutionContext
    ) async throws -> GraphQLHTTPTransportResponse
}

struct GraphQLExecutionRequest: Sendable {
    var endpoint: URL
    var method: String
    var headers: [(String, String)]
    var body: Data?
    var timeout: TimeInterval
}

struct GraphQLHTTPTransportResponse: Sendable {
    var statusCode: Int?
    var headers: [(String, String)]
    var body: Data
    var finalURL: URL?
    var metrics: RequestMetrics?
}

struct URLSessionGraphQLHTTPTransport: GraphQLHTTPTransport {
    private let sessionManager: RESTSessionManager
    private let maxResponseBytes: Int

    init(
        sessionManager: RESTSessionManager = RESTSessionManager(),
        maxResponseBytes: Int = 50 * 1024 * 1024
    ) {
        self.sessionManager = sessionManager
        self.maxResponseBytes = maxResponseBytes
    }

    func execute(
        request: GraphQLExecutionRequest,
        context: ExecutionContext
    ) async throws -> GraphQLHTTPTransportResponse {
        let key = RESTSessionManager.SessionKey(
            projectID: context.projectID,
            redirectPolicy: .follow,
            tlsPolicy: .systemDefault
        )
        let (session, delegate) = await sessionManager.session(for: key)

        var urlRequest = URLRequest(url: request.endpoint)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = request.timeout
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            if data.count > maxResponseBytes {
                throw GraphQLExecutionError.responseTooLarge(data.count)
            }
            let http = response as? HTTPURLResponse
            var metrics = RequestMetricsCollector.collect(from: delegate.latestMetrics)
            return GraphQLHTTPTransportResponse(
                statusCode: http?.statusCode,
                headers: headerPairs(from: http),
                body: data,
                finalURL: http?.url ?? response.url,
                metrics: metrics
            )
        } catch let error as GraphQLExecutionError {
            throw error
        } catch let urlError as URLError {
            throw mapURLError(urlError)
        } catch is CancellationError {
            throw GraphQLExecutionError.cancelled
        } catch {
            throw GraphQLExecutionError.transport(.unknown(error.localizedDescription))
        }
    }

    private func headerPairs(from response: HTTPURLResponse?) -> [(String, String)] {
        guard let response else { return [] }
        return response.allHeaderFields.compactMap { key, value in
            guard let name = key as? String else { return nil }
            return (name, String(describing: value))
        }
        .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    private func mapURLError(_ error: URLError) -> GraphQLExecutionError {
        switch error.code {
        case .timedOut: .timeout
        case .cancelled: .cancelled
        case .cannotFindHost, .dnsLookupFailed: .transport(.dnsFailure(error.localizedDescription))
        case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            .transport(.connectionFailure(error.localizedDescription))
        default: .transport(.unknown(error.localizedDescription))
        }
    }
}

protocol GraphQLSubscriptionTransport: Sendable {}
