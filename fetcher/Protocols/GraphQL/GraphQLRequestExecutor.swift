import Foundation

struct GraphQLRequestExecutor: APIRequestExecutor {
    let kind: APIProtocolKind = .graphql
    private let transport: any GraphQLHTTPTransport
    private let languageService: any GraphQLLanguageService
    private let resolver: VariableResolver

    init(
        transport: any GraphQLHTTPTransport = URLSessionGraphQLHTTPTransport(),
        languageService: (any GraphQLLanguageService)? = nil,
        resolver: VariableResolver = VariableResolver()
    ) {
        self.transport = transport
        self.languageService = languageService ?? GraphQLLanguageServiceFactory.makeDefault()
        self.resolver = resolver
    }

    func execute(
        draft: APIRequestDraft,
        context: ExecutionContext
    ) async throws -> APIExecutionResult {
        guard case .graphql(let graphqlDraft) = draft else {
            throw APIExecutionFailure.unsupportedProtocol(draft.protocolKind)
        }
        return try await execute(draft: graphqlDraft, context: context)
    }

    func execute(
        draft: GraphQLRequestDraft,
        context: ExecutionContext
    ) async throws -> APIExecutionResult {
        let startedAt = Date()
        let scope = VariableScope(values: draft.variables.merging(draft.secretVariables) { _, secret in secret })

        let endpointTemplate = draft.endpoint.isEmpty ? draft.baseURL : draft.endpoint
        let resolvedEndpoint = try resolver.resolve(endpointTemplate, scope: scope)
        if let missing = resolvedEndpoint.unresolvedNames.first {
            throw GraphQLExecutionError.unresolvedVariable(missing)
        }

        guard let endpointURL = makeURL(from: resolvedEndpoint.value, baseURL: draft.baseURL) else {
            throw GraphQLExecutionError.invalidEndpoint(resolvedEndpoint.value)
        }

        let document = try resolver.resolve(draft.document, scope: scope).value
        let variablesText = try resolver.resolve(draft.variablesJSON, scope: scope).value

        let syntaxIssues = languageService.syntaxDiagnostics(in: document)
        if syntaxIssues.contains(where: { $0.severity == .error }) {
            throw GraphQLExecutionError.invalidDocument(syntaxIssues.map(\.message).joined(separator: "\n"))
        }

        let parsed = try languageService.parseDocument(document)
        let selectedOperation = selectOperation(from: parsed, named: draft.operationName)

        let method: String
        switch draft.methodPreference {
        case .post:
            method = "POST"
        case .getForQueries:
            if selectedOperation?.kind == .mutation {
                throw GraphQLExecutionError.mutationRequiresPOST
            }
            method = selectedOperation?.kind == .query ? "GET" : "POST"
        }

        if !variablesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let data = variablesText.data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data)) != nil else {
                throw GraphQLExecutionError.invalidVariables("Variables must be valid JSON.")
            }
        }

        var headers = draft.headers
            .filter(\.isEnabled)
            .filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { ($0.key, $0.value) }

        applyAuth(draft: draft, to: &headers)

        let timeout = draft.timeoutSeconds ?? 30
        let transportRequest: GraphQLExecutionRequest

        if method == "GET" {
            guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
                throw GraphQLExecutionError.invalidEndpoint(endpointURL.absoluteString)
            }
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "query", value: document))
            if let operationName = draft.operationName, !operationName.isEmpty {
                items.append(URLQueryItem(name: "operationName", value: operationName))
            }
            if !variablesText.isEmpty, variablesText != "{}" {
                items.append(URLQueryItem(name: "variables", value: variablesText))
            }
            if let extensions = draft.extensionsJSON, !extensions.isEmpty {
                items.append(URLQueryItem(name: "extensions", value: extensions))
            }
            components.queryItems = items
            guard let url = components.url else {
                throw GraphQLExecutionError.invalidEndpoint(endpointURL.absoluteString)
            }
            if !headers.contains(where: { $0.0.caseInsensitiveCompare("Accept") == .orderedSame }) {
                headers.append(("Accept", "application/graphql-response+json, application/json;q=0.9"))
            }
            transportRequest = GraphQLExecutionRequest(
                endpoint: url,
                method: "GET",
                headers: headers,
                body: nil,
                timeout: timeout
            )
        } else {
            var payload: [String: Any] = ["query": document]
            if let operationName = draft.operationName, !operationName.isEmpty {
                payload["operationName"] = operationName
            }
            if let variablesData = variablesText.data(using: .utf8),
               let variablesObject = try? JSONSerialization.jsonObject(with: variablesData) {
                payload["variables"] = variablesObject
            }
            if let extensions = draft.extensionsJSON,
               let extensionsData = extensions.data(using: .utf8),
               let extensionsObject = try? JSONSerialization.jsonObject(with: extensionsData) {
                payload["extensions"] = extensionsObject
            }
            let body = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            if !headers.contains(where: { $0.0.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
                headers.append(("Content-Type", "application/json"))
            }
            if !headers.contains(where: { $0.0.caseInsensitiveCompare("Accept") == .orderedSame }) {
                headers.append(("Accept", "application/graphql-response+json, application/json;q=0.9"))
            }
            transportRequest = GraphQLExecutionRequest(
                endpoint: endpointURL,
                method: "POST",
                headers: headers,
                body: body,
                timeout: timeout
            )
        }

        let response = try await transport.execute(request: transportRequest, context: context)
        let finishedAt = Date()
        let parsedResponse = GraphQLResponseParser.parse(body: response.body)

        var metrics = response.metrics ?? RequestMetrics(redirectCount: 0)
        if metrics.totalDuration == nil {
            metrics.totalDuration = finishedAt.timeIntervalSince(startedAt)
        }

        let artifact = GraphQLResponseArtifact(
            id: UUID(),
            requestID: draft.requestID,
            startedAt: startedAt,
            finishedAt: finishedAt,
            endpointURL: response.finalURL ?? endpointURL,
            httpStatusCode: response.statusCode,
            httpHeaders: response.headers,
            rawBody: response.body,
            dataJSON: parsedResponse.dataJSON,
            errors: parsedResponse.errors,
            extensionsJSON: parsedResponse.extensionsJSON,
            metrics: metrics,
            error: nil
        )
        return .graphql(artifact)
    }

    private func selectOperation(
        from document: GraphQLDocument,
        named name: String?
    ) -> GraphQLOperationInfo? {
        if let name, !name.isEmpty {
            return document.operations.first { $0.name == name }
        }
        if document.operations.count == 1 {
            return document.operations.first
        }
        return document.operations.first { $0.name == nil } ?? document.operations.first
    }

    private func makeURL(from endpoint: String, baseURL: String) -> URL? {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute
        }
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let baseURL = URL(string: base) else {
            return URL(string: trimmed)
        }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    private func applyAuth(draft: GraphQLRequestDraft, to headers: inout [(String, String)]) {
        switch draft.authKind {
        case .none, .inherit:
            break
        case .bearer:
            if let token = draft.bearerToken, !token.isEmpty {
                let value = draft.bearerPrefix.isEmpty ? token : "\(draft.bearerPrefix) \(token)"
                headers.removeAll { $0.0.caseInsensitiveCompare("Authorization") == .orderedSame }
                headers.append(("Authorization", value))
            }
        case .basic:
            let username = draft.basicUsername ?? ""
            let password = draft.basicPassword ?? ""
            if let data = "\(username):\(password)".data(using: .utf8) {
                headers.removeAll { $0.0.caseInsensitiveCompare("Authorization") == .orderedSame }
                headers.append(("Authorization", "Basic \(data.base64EncodedString())"))
            }
        case .apiKey:
            guard let name = draft.apiKeyName, let value = draft.apiKeyValue else { return }
            if draft.apiKeyLocation == .header {
                headers.removeAll { $0.0.caseInsensitiveCompare(name) == .orderedSame }
                headers.append((name, value))
            }
        }
    }
}

enum GraphQLResponseParser {
    struct Parsed {
        var dataJSON: String?
        var errors: [GraphQLResponseError]
        var extensionsJSON: String?
    }

    static func parse(body: Data) -> Parsed {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return Parsed(dataJSON: nil, errors: [], extensionsJSON: nil)
        }

        let dataJSON: String?
        if let data = object["data"], JSONSerialization.isValidJSONObject(data) || data is NSNull {
            if data is NSNull {
                dataJSON = "null"
            } else if let encoded = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]),
                      let text = String(data: encoded, encoding: .utf8) {
                dataJSON = text
            } else {
                dataJSON = nil
            }
        } else {
            dataJSON = nil
        }

        var errors: [GraphQLResponseError] = []
        if let rawErrors = object["errors"] as? [[String: Any]] {
            for raw in rawErrors {
                let message = raw["message"] as? String ?? "Unknown GraphQL error"
                let path = ((raw["path"] as? [Any]) ?? []).map { String(describing: $0) }
                let locations: [GraphQLErrorLocation] = ((raw["locations"] as? [[String: Any]]) ?? []).compactMap { location in
                    guard let line = location["line"] as? Int, let column = location["column"] as? Int else {
                        return nil
                    }
                    return GraphQLErrorLocation(line: line, column: column)
                }
                var extensionsJSON: String?
                if let extensions = raw["extensions"], JSONSerialization.isValidJSONObject(extensions),
                   let encoded = try? JSONSerialization.data(withJSONObject: extensions, options: [.prettyPrinted]),
                   let text = String(data: encoded, encoding: .utf8) {
                    extensionsJSON = text
                }
                errors.append(GraphQLResponseError(
                    message: message,
                    path: path,
                    locations: locations,
                    extensionsJSON: extensionsJSON
                ))
            }
        }

        let extensionsJSON: String?
        if let extensions = object["extensions"], JSONSerialization.isValidJSONObject(extensions),
           let encoded = try? JSONSerialization.data(withJSONObject: extensions, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: encoded, encoding: .utf8) {
            extensionsJSON = text
        } else {
            extensionsJSON = nil
        }

        return Parsed(dataJSON: dataJSON, errors: errors, extensionsJSON: extensionsJSON)
    }
}
