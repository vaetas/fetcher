import Foundation

struct RESTRequestBuilder: Sendable {
    private let variableResolver: any VariableResolving

    init(variableResolver: any VariableResolving = VariableResolver()) {
        self.variableResolver = variableResolver
    }

    func build(_ draft: RESTRequestDraft) async throws -> (ResolvedRESTRequest, PreparedRequestPreview, [String]) {
        let validation = RESTRequestValidator.validate(draft)
        let blocking = validation.filter(\.isBlocking)
        if !blocking.isEmpty {
            throw RESTExecutionError.validation(blocking)
        }

        var warnings = validation
            .filter { !$0.isBlocking }
            .map { RequestWarning(message: $0.message) }

        let scope = VariableScope(values: draft.variables.merging(draft.secretVariables) { _, secret in secret })

        let resolvedEndpoint = try variableResolver.resolve(draft.endpoint, scope: scope)
        warnings.append(contentsOf: resolvedEndpoint.warnings)
        if let unresolved = resolvedEndpoint.unresolvedNames.first {
            throw RESTExecutionError.unresolvedVariable(unresolved)
        }

        var pathValues: [String: String] = [:]
        for entry in draft.pathParameters where entry.isEnabled {
            let resolved = try variableResolver.resolve(entry.value, scope: scope)
            warnings.append(contentsOf: resolved.warnings)
            if let unresolved = resolved.unresolvedNames.first {
                throw RESTExecutionError.unresolvedVariable(unresolved)
            }
            pathValues[entry.key] = resolved.value
        }

        let pathApplied = applyPathParameters(endpoint: resolvedEndpoint.value, values: pathValues)
        let url = try buildURL(
            endpoint: pathApplied,
            baseURL: draft.baseURL,
            queryParameters: draft.queryParameters,
            scope: scope,
            warnings: &warnings
        )

        var headers: [(String, String)] = []
        for entry in draft.projectDefaultHeaders where entry.isEnabled && !entry.key.isEmpty {
            let resolved = try variableResolver.resolve(entry.value, scope: scope)
            warnings.append(contentsOf: resolved.warnings)
            headers.append((entry.key, resolved.value))
        }
        for entry in draft.headers where entry.isEnabled && !entry.key.isEmpty {
            let resolved = try variableResolver.resolve(entry.value, scope: scope)
            warnings.append(contentsOf: resolved.warnings)
            headers.removeAll { $0.0.caseInsensitiveCompare(entry.key) == .orderedSame }
            headers.append((entry.key, resolved.value))
        }

        let bodyTextResolved = try variableResolver.resolve(draft.bodyText, scope: scope)
        warnings.append(contentsOf: bodyTextResolved.warnings)
        let encoded = try RESTBodyEncoder.encode(mode: draft.bodyMode, text: bodyTextResolved.value)
        warnings.append(contentsOf: encoded.warnings)

        if let contentType = encoded.contentType,
           !headers.contains(where: { $0.0.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
            headers.append(("Content-Type", contentType))
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = draft.method
        for (name, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        urlRequest.httpBody = encoded.data
        let timeout = draft.timeoutSeconds ?? 30
        urlRequest.timeoutInterval = timeout

        var context = ResolvedRequestContext(url: url, headers: headers, queryItems: [], secretsUsed: Array(draft.secretVariables.values))
        let effectiveAuth = draft.authKind
        let strategy = AuthStrategyFactory.strategy(for: draft, effectiveKind: effectiveAuth)
        try await strategy.apply(to: &urlRequest, resolvedContext: &context)

        guard let finalURL = urlRequest.url else {
            throw RESTExecutionError.invalidEndpoint("Resolved URL is missing.")
        }

        let resolved = ResolvedRESTRequest(
            method: draft.method.uppercased(),
            url: finalURL,
            headers: context.headers,
            body: urlRequest.httpBody,
            timeout: timeout,
            redirectPolicy: draft.redirectPolicy,
            tlsPolicy: draft.tlsPolicy,
            warnings: warnings
        )

        let bodyPreview: String?
        if let data = encoded.data {
            bodyPreview = String(data: data, encoding: .utf8)
        } else {
            bodyPreview = nil
        }

        let preview = PreparedRequestPreview(
            resolvedURL: finalURL.absoluteString,
            headers: SecretRedactor.redactHeaders(context.headers),
            bodyPreview: bodyPreview,
            warnings: warnings
        )

        return (resolved, preview, context.secretsUsed)
    }

    private func applyPathParameters(endpoint: String, values: [String: String]) -> String {
        values.reduce(endpoint) { partial, pair in
            let encoded = pair.value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pair.value
            return partial.replacingOccurrences(of: "{\(pair.key)}", with: encoded)
        }
    }

    private func buildURL(
        endpoint: String,
        baseURL: String,
        queryParameters: [KeyValueEntry],
        scope: VariableScope,
        warnings: inout [RequestWarning]
    ) throws -> URL {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        var components: URLComponents

        if let absolute = URLComponents(string: trimmed),
           let scheme = absolute.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            components = absolute
        } else {
            let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !base.isEmpty else {
                throw RESTExecutionError.invalidEndpoint("Relative endpoint requires a base URL.")
            }
            guard var baseComponents = URLComponents(string: base) else {
                throw RESTExecutionError.invalidEndpoint("Base URL is invalid: \(base)")
            }
            let basePath = baseComponents.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let relativePath = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
            if basePath.isEmpty {
                baseComponents.path = "/" + relativePath
            } else {
                baseComponents.path = "/" + basePath + "/" + relativePath
            }
            components = baseComponents
        }

        var items = components.queryItems ?? []
        for entry in queryParameters where entry.isEnabled && !entry.key.isEmpty {
            let resolved = try variableResolver.resolve(entry.value, scope: scope)
            warnings.append(contentsOf: resolved.warnings)
            if let unresolved = resolved.unresolvedNames.first {
                throw RESTExecutionError.unresolvedVariable(unresolved)
            }
            items.append(URLQueryItem(name: entry.key, value: resolved.value))
        }
        if !items.isEmpty {
            components.queryItems = items
        }

        guard let url = components.url else {
            throw RESTExecutionError.invalidEndpoint("Unable to construct URL from \(trimmed)")
        }
        return url
    }
}
