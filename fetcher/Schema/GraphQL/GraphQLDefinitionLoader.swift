import Foundation

struct GraphQLDefinitionLoader: DefinitionLoader, Sendable {
    var kind: APIDefinitionKind { .graphql }

    private let languageService: any GraphQLLanguageService
    private let bookmarkStore: SecurityScopedBookmarkStore
    private let urlSession: URLSession

    init(
        languageService: any GraphQLLanguageService = BuiltinGraphQLLanguageService(),
        bookmarkStore: SecurityScopedBookmarkStore = SecurityScopedBookmarkStore(),
        urlSession: URLSession = .shared
    ) {
        self.languageService = languageService
        self.bookmarkStore = bookmarkStore
        self.urlSession = urlSession
    }

    func refresh(
        sourceID: UUID,
        configData: Data,
        artifactStore: SchemaArtifactStore
    ) async throws -> DefinitionRefreshResult {
        let config = try decodeConfig(configData)
        switch config {
        case .localSDL(let source):
            return try await refreshLocalSDL(sourceID: sourceID, source: source, artifactStore: artifactStore)
        case .localIntrospectionJSON(let source):
            return try await refreshLocalIntrospectionJSON(sourceID: sourceID, source: source, artifactStore: artifactStore)
        case .endpointIntrospection(let source):
            return try await refreshEndpointIntrospection(sourceID: sourceID, source: source, artifactStore: artifactStore)
        case .remoteDocument(let source):
            return try await refreshRemoteDocument(sourceID: sourceID, source: source, artifactStore: artifactStore)
        }
    }

    private func decodeConfig(_ data: Data) throws -> GraphQLDefinitionConfig {
        do {
            return try JSONDecoder().decode(GraphQLDefinitionConfig.self, from: data)
        } catch {
            throw DefinitionRefreshError.invalidConfiguration("Invalid GraphQL definition configuration.")
        }
    }

    private func refreshLocalSDL(
        sourceID: UUID,
        source: GraphQLLocalSDLSource,
        artifactStore: SchemaArtifactStore
    ) async throws -> DefinitionRefreshResult {
        guard let bookmarkData = source.bookmarkData else {
            throw DefinitionRefreshError.sourceUnavailable("No bookmark is available for the selected SDL source.")
        }

        let mergedSDL = try bookmarkStore.withAccessing(bookmark: bookmarkData) { url in
            try readGraphQLSources(at: url, isDirectory: source.isDirectory)
        }

        let snapshot = try languageService.loadSDL(mergedSDL)
        return try writeSnapshotArtifacts(
            sourceID: sourceID,
            snapshot: snapshot,
            mergedSDL: mergedSDL,
            introspectionJSON: nil,
            sourceKind: source.isDirectory ? GraphQLDefinitionSourceKind.localSDLDirectory.rawValue : GraphQLDefinitionSourceKind.localSDLFile.rawValue,
            artifactStore: artifactStore
        )
    }

    private func refreshLocalIntrospectionJSON(
        sourceID: UUID,
        source: GraphQLLocalIntrospectionJSONSource,
        artifactStore: SchemaArtifactStore
    ) async throws -> DefinitionRefreshResult {
        guard let bookmarkData = source.bookmarkData else {
            throw DefinitionRefreshError.sourceUnavailable("No bookmark is available for the selected introspection JSON file.")
        }

        let jsonData = try bookmarkStore.withAccessing(bookmark: bookmarkData) { url in
            try readLimitedData(from: url)
        }

        return try await normalizeIntrospection(
            sourceID: sourceID,
            jsonData: jsonData,
            sourceKind: GraphQLDefinitionSourceKind.localIntrospectionJSON.rawValue,
            artifactStore: artifactStore
        )
    }

    private func refreshEndpointIntrospection(
        sourceID: UUID,
        source: GraphQLIntrospectionSource,
        artifactStore: SchemaArtifactStore
    ) async throws -> DefinitionRefreshResult {
        guard let endpointURL = URL(string: source.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw DefinitionRefreshError.invalidConfiguration("Introspection endpoint URL is invalid.")
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = SchemaResourceLimits.schemaRefreshTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for header in source.headers where header.isEnabled && !header.key.isEmpty {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }
        request.httpBody = try JSONEncoder().encode(IntrospectionRequest(query: Self.standardIntrospectionQuery))

        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DefinitionRefreshError.sourceUnavailable("Introspection request failed with status \(http.statusCode).")
        }
        if data.count > SchemaResourceLimits.maxTotalSourceBytes {
            throw DefinitionRefreshError.limitExceeded("Introspection response exceeds size limit.")
        }

        return try await normalizeIntrospection(
            sourceID: sourceID,
            jsonData: data,
            sourceKind: GraphQLDefinitionSourceKind.endpointIntrospection.rawValue,
            artifactStore: artifactStore
        )
    }

    private func refreshRemoteDocument(
        sourceID: UUID,
        source: GraphQLRemoteDocumentSource,
        artifactStore: SchemaArtifactStore
    ) async throws -> DefinitionRefreshResult {
        guard let url = URL(string: source.url.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw DefinitionRefreshError.invalidConfiguration("Remote document URL is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = SchemaResourceLimits.schemaRefreshTimeout
        for header in source.headers where header.isEnabled && !header.key.isEmpty {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }

        let (data, response) = try await urlSession.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DefinitionRefreshError.sourceUnavailable("Remote document request failed with status \(http.statusCode).")
        }
        if data.count > SchemaResourceLimits.maxTotalSourceBytes {
            throw DefinitionRefreshError.limitExceeded("Remote document exceeds size limit.")
        }

        if source.isIntrospectionJSON {
            return try await normalizeIntrospection(
                sourceID: sourceID,
                jsonData: data,
                sourceKind: GraphQLDefinitionSourceKind.remoteIntrospectionJSONURL.rawValue,
                artifactStore: artifactStore
            )
        }

        guard let sdl = String(data: data, encoding: .utf8) else {
            throw DefinitionRefreshError.compilationFailed("Remote document is not valid UTF-8 text.")
        }
        if sdl.utf8.count > SchemaResourceLimits.maxGraphQLSDLBytes {
            throw DefinitionRefreshError.limitExceeded("Remote SDL exceeds size limit.")
        }

        let snapshot = try languageService.loadSDL(sdl)
        return try writeSnapshotArtifacts(
            sourceID: sourceID,
            snapshot: snapshot,
            mergedSDL: sdl,
            introspectionJSON: nil,
            sourceKind: GraphQLDefinitionSourceKind.remoteSDLURL.rawValue,
            artifactStore: artifactStore
        )
    }

    private func normalizeIntrospection(
        sourceID: UUID,
        jsonData: Data,
        sourceKind: String,
        artifactStore: SchemaArtifactStore
    ) async throws -> DefinitionRefreshResult {
        let snapshot = try languageService.loadIntrospectionJSON(jsonData)
        let sdl = GraphQLSDLSerializer.render(snapshot)
        return try writeSnapshotArtifacts(
            sourceID: sourceID,
            snapshot: snapshot,
            mergedSDL: sdl,
            introspectionJSON: jsonData,
            sourceKind: sourceKind,
            artifactStore: artifactStore
        )
    }

    private func writeSnapshotArtifacts(
        sourceID: UUID,
        snapshot: GraphQLSchemaSnapshot,
        mergedSDL: String,
        introspectionJSON: Data?,
        sourceKind: String,
        artifactStore: SchemaArtifactStore
    ) throws -> DefinitionRefreshResult {
        let fingerprint = ContentFingerprint.sha256(of: mergedSDL)
        _ = try artifactStore.writeNormalized(
            sourceID: sourceID,
            fingerprint: fingerprint,
            relativePath: "schema.graphql",
            data: Data(mergedSDL.utf8)
        )
        if let introspectionJSON {
            _ = try artifactStore.writeNormalized(
                sourceID: sourceID,
                fingerprint: fingerprint,
                relativePath: "introspection.json",
                data: introspectionJSON
            )
        }

        let diagnostics = languageService.syntaxDiagnostics(in: mergedSDL)
        try artifactStore.writeDiagnostics(sourceID: sourceID, fingerprint: fingerprint, diagnostics: diagnostics)

        var normalizedPaths = ["schema.graphql"]
        if introspectionJSON != nil {
            normalizedPaths.append("introspection.json")
        }

        return DefinitionRefreshResult(
            fingerprint: fingerprint,
            snapshotID: snapshot.id.rawValue,
            diagnostics: diagnostics,
            normalizedRelativePaths: normalizedPaths
        )
    }

    private func readGraphQLSources(at url: URL, isDirectory: Bool) throws -> String {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw DefinitionRefreshError.sourceUnavailable("GraphQL source path does not exist.")
        }

        let urls: [URL]
        if isDirectory || isDir.boolValue {
            urls = try discoverGraphQLFiles(in: url)
        } else {
            urls = [url]
        }

        guard !urls.isEmpty else {
            throw DefinitionRefreshError.sourceUnavailable("No GraphQL schema files were found.")
        }

        var mergedParts: [String] = []
        var totalBytes = 0
        for fileURL in urls.sorted(by: { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) {
            let data = try readLimitedData(from: fileURL)
            totalBytes += data.count
            if totalBytes > SchemaResourceLimits.maxTotalSourceBytes {
                throw DefinitionRefreshError.limitExceeded("Combined GraphQL sources exceed size limit.")
            }
            if let text = String(data: data, encoding: .utf8) {
                mergedParts.append(text)
            }
        }

        let merged = mergedParts.joined(separator: "\n\n")
        if merged.utf8.count > SchemaResourceLimits.maxGraphQLSDLBytes {
            throw DefinitionRefreshError.limitExceeded("Merged GraphQL SDL exceeds size limit.")
        }
        if !containsTypeSystemDefinition(merged) {
            throw DefinitionRefreshError.compilationFailed("Selected GraphQL source does not contain schema type definitions.")
        }
        return merged
    }

    private func discoverGraphQLFiles(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let extensions = Set(["graphql", "graphqls", "gql"])
        var results: [URL] = []
        var fileCount = 0

        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw DefinitionRefreshError.sourceUnavailable("Unable to enumerate GraphQL source directory.")
        }

        for case let fileURL as URL in enumerator {
            fileCount += 1
            if fileCount > SchemaResourceLimits.maxFileCount {
                throw DefinitionRefreshError.limitExceeded("GraphQL source directory exceeds file count limit.")
            }
            let ext = fileURL.pathExtension.lowercased()
            if extensions.contains(ext) {
                results.append(fileURL)
            }
        }
        return results
    }

    private func readLimitedData(from url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        if let size = values.fileSize, size > SchemaResourceLimits.maxIndividualFileBytes {
            throw DefinitionRefreshError.limitExceeded("File '\(url.lastPathComponent)' exceeds size limit.")
        }
        let data = try Data(contentsOf: url)
        if data.count > SchemaResourceLimits.maxIndividualFileBytes {
            throw DefinitionRefreshError.limitExceeded("File '\(url.lastPathComponent)' exceeds size limit.")
        }
        return data
    }

    private func containsTypeSystemDefinition(_ source: String) -> Bool {
        let keywords = ["type ", "interface ", "union ", "enum ", "input ", "scalar ", "schema ", "directive "]
        return keywords.contains { source.contains($0) }
    }

    private struct IntrospectionRequest: Encodable {
        let query: String
    }

    static let standardIntrospectionQuery = """
    query IntrospectionQuery {
      __schema {
        queryType { name }
        mutationType { name }
        subscriptionType { name }
        types {
          kind
          name
          description
          fields(includeDeprecated: true) {
            name
            description
            args {
              name
              description
              type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } } } }
              defaultValue
            }
            type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } } } }
            isDeprecated
            deprecationReason
          }
          inputFields {
            name
            description
            type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } } } }
            defaultValue
          }
          interfaces { kind name ofType { kind name } }
          enumValues(includeDeprecated: true) {
            name
            description
            isDeprecated
            deprecationReason
          }
          possibleTypes { kind name ofType { kind name } }
        }
        directives {
          name
          description
          locations
          args {
            name
            description
            type { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name ofType { kind name } } } } } } } } }
            defaultValue
          }
        }
      }
    }
    """
}
