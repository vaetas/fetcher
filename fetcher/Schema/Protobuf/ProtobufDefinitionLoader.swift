import Foundation

struct ProtobufDefinitionLoader: DefinitionLoader, Sendable {
    var kind: APIDefinitionKind { .protobuf }

    private let runtime: any DynamicProtobufRuntime
    private let compiler: any ProtoSchemaCompiler
    private let bookmarkStore: SecurityScopedBookmarkStore
    private let sourceReader: SchemaSourceReader
    private let urlSession: URLSession

    init(
        runtime: any DynamicProtobufRuntime = BuiltinDynamicProtobufRuntime(),
        compiler: any ProtoSchemaCompiler = ProtocSchemaCompiler(),
        bookmarkStore: SecurityScopedBookmarkStore = SecurityScopedBookmarkStore(),
        sourceReader: SchemaSourceReader = SchemaSourceReader(),
        urlSession: URLSession = .shared
    ) {
        self.runtime = runtime
        self.compiler = compiler
        self.bookmarkStore = bookmarkStore
        self.sourceReader = sourceReader
        self.urlSession = urlSession
    }

    func refresh(
        sourceID: UUID,
        configData: Data,
        artifactStore: SchemaArtifactStore
    ) async throws -> DefinitionRefreshResult {
        let config = try decodeConfig(configData)
        switch config {
        case .localDescriptorSet(let source):
            return try await refreshLocalDescriptorSet(sourceID: sourceID, source: source, artifactStore: artifactStore)
        case .localProto(let source):
            return try await refreshLocalProto(sourceID: sourceID, source: source, artifactStore: artifactStore)
        case .serverReflection(let source):
            return try await refreshServerReflection(sourceID: sourceID, source: source, artifactStore: artifactStore)
        case .remoteProto(let source):
            return try await refreshRemoteProto(sourceID: sourceID, source: source, artifactStore: artifactStore)
        case .remoteDescriptorSet(let source):
            return try await refreshRemoteDescriptorSet(sourceID: sourceID, source: source, artifactStore: artifactStore)
        }
    }

    private func decodeConfig(_ data: Data) throws -> ProtobufDefinitionConfig {
        do {
            return try JSONDecoder().decode(ProtobufDefinitionConfig.self, from: data)
        } catch {
            throw DefinitionRefreshError.invalidConfiguration("Invalid protobuf definition configuration.")
        }
    }

    private func refreshLocalDescriptorSet(
        sourceID: UUID,
        source: GRPCLocalDescriptorSetSource,
        artifactStore: SchemaArtifactStore
    ) async throws -> DefinitionRefreshResult {
        guard let bookmarkData = source.bookmarkData else {
            throw DefinitionRefreshError.sourceUnavailable("No bookmark is available for the selected descriptor set.")
        }

        let descriptorData = try bookmarkStore.withAccessing(bookmark: bookmarkData) { url in
            try sourceReader.readLimitedData(from: url)
        }

        return try writeDescriptorArtifacts(
            sourceID: sourceID,
            descriptorData: descriptorData,
            sourceKind: ProtobufDefinitionSourceKind.localDescriptorSet.rawValue,
            artifactStore: artifactStore,
            extraDiagnostics: []
        )
    }

    private func refreshLocalProto(
        sourceID: UUID,
        source: GRPCLocalProtoSource,
        artifactStore: SchemaArtifactStore
    ) async throws -> DefinitionRefreshResult {
        guard !source.rootBookmarkData.isEmpty else {
            throw DefinitionRefreshError.sourceUnavailable("No proto root bookmarks are available.")
        }

        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("fetcher-proto-\(sourceID.uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: stagingRoot)
        defer { try? FileManager.default.removeItem(at: stagingRoot) }

        let bookmarks = source.rootBookmarkData + source.importRootBookmarkData
        let staged = try bookmarkStore.withAccessing(bookmarks: bookmarks) { urls in
            let rootURLs = Array(urls.prefix(source.rootBookmarkData.count))
            let importRootURLs = Array(urls.dropFirst(source.rootBookmarkData.count))
            return try sourceReader.stageProtoSources(
                from: rootURLs,
                importRoots: importRootURLs,
                into: stagingRoot
            )
        }

        guard !staged.rootFiles.isEmpty else {
            throw DefinitionRefreshError.sourceUnavailable("No .proto files were found in the selected source.")
        }

        let compiled = try await compiler.compile(source: staged)

        return try writeDescriptorArtifacts(
            sourceID: sourceID,
            descriptorData: compiled.data,
            sourceKind: source.isDirectory
                ? ProtobufDefinitionSourceKind.localProtoDirectory.rawValue
                : ProtobufDefinitionSourceKind.localProtoFiles.rawValue,
            artifactStore: artifactStore,
            extraDiagnostics: compiled.diagnostics
        )
    }

    private func refreshServerReflection(
        sourceID: UUID,
        source: GRPCReflectionSource,
        artifactStore: SchemaArtifactStore
    ) async throws -> DefinitionRefreshResult {
        let client = GRPCReflectionClient(endpoint: source.endpoint, tls: source.tls)
        let descriptorData = try await client.fetchDescriptorSet(
            metadata: source.metadata.filter(\.isEnabled).map { ($0.key, $0.value) }
        )
        return try writeDescriptorArtifacts(
            sourceID: sourceID,
            descriptorData: descriptorData,
            sourceKind: ProtobufDefinitionSourceKind.serverReflection.rawValue,
            artifactStore: artifactStore,
            extraDiagnostics: []
        )
    }

    private func refreshRemoteProto(
        sourceID: UUID,
        source: GRPCRemoteProtoSource,
        artifactStore: SchemaArtifactStore
    ) async throws -> DefinitionRefreshResult {
        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("fetcher-remote-proto-\(sourceID.uuidString)", isDirectory: true)
        try? FileManager.default.removeItem(at: stagingRoot)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

        var rootFiles: [URL] = []
        for remotePath in source.rootFiles {
            let data = try await fetchRemoteData(
                urlString: remotePath,
                headers: source.headers
            )
            let fileName = URL(string: remotePath)?.lastPathComponent ?? "root.proto"
            let destination = stagingRoot.appendingPathComponent("roots").appendingPathComponent(fileName)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destination)
            rootFiles.append(destination)
        }

        var importRoots: [URL] = []
        for (index, remoteImportRoot) in source.importRoots.enumerated() {
            let data = try await fetchRemoteData(urlString: remoteImportRoot, headers: source.headers)
            let destination = stagingRoot.appendingPathComponent("imports/\(index)")
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let fileName = URL(string: remoteImportRoot)?.lastPathComponent ?? "import.proto"
            try data.write(to: destination.appendingPathComponent(fileName))
            importRoots.append(destination)
        }

        let staged = StagedProtoSource(rootFiles: rootFiles, importRoots: importRoots, stagingRoot: stagingRoot)
        let compiled = try await compiler.compile(source: staged)
        defer { try? FileManager.default.removeItem(at: stagingRoot) }

        return try writeDescriptorArtifacts(
            sourceID: sourceID,
            descriptorData: compiled.data,
            sourceKind: ProtobufDefinitionSourceKind.remoteProtoURL.rawValue,
            artifactStore: artifactStore,
            extraDiagnostics: compiled.diagnostics
        )
    }

    private func refreshRemoteDescriptorSet(
        sourceID: UUID,
        source: GRPCRemoteDescriptorSetSource,
        artifactStore: SchemaArtifactStore
    ) async throws -> DefinitionRefreshResult {
        let descriptorData = try await fetchRemoteData(urlString: source.url, headers: source.headers)
        return try writeDescriptorArtifacts(
            sourceID: sourceID,
            descriptorData: descriptorData,
            sourceKind: ProtobufDefinitionSourceKind.remoteDescriptorSetURL.rawValue,
            artifactStore: artifactStore,
            extraDiagnostics: []
        )
    }

    private func fetchRemoteData(urlString: String, headers: [EnabledKeyValue]) async throws -> Data {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw DefinitionRefreshError.invalidConfiguration("Remote URL is invalid.")
        }

        var currentURL = url
        var redirectCount = 0

        while true {
            var request = URLRequest(url: currentURL)
            request.httpMethod = "GET"
            request.timeoutInterval = SchemaResourceLimits.schemaRefreshTimeout
            for header in headers where header.isEnabled && !header.key.isEmpty {
                request.setValue(header.value, forHTTPHeaderField: header.key)
            }

            let (data, response) = try await urlSession.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (300..<400).contains(http.statusCode), let location = http.value(forHTTPHeaderField: "Location"), let nextURL = URL(string: location, relativeTo: currentURL) {
                    redirectCount += 1
                    if redirectCount > SchemaResourceLimits.maxRemoteRedirects {
                        throw DefinitionRefreshError.limitExceeded("Remote fetch exceeded redirect limit.")
                    }
                    currentURL = nextURL.absoluteURL
                    continue
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw DefinitionRefreshError.sourceUnavailable("Remote fetch failed with status \(http.statusCode).")
                }
            }

            if data.count > SchemaResourceLimits.maxTotalSourceBytes {
                throw DefinitionRefreshError.limitExceeded("Remote resource exceeds size limit.")
            }
            return data
        }
    }

    private func writeDescriptorArtifacts(
        sourceID: UUID,
        descriptorData: Data,
        sourceKind: String,
        artifactStore: SchemaArtifactStore,
        extraDiagnostics: [EditorDiagnostic]
    ) throws -> DefinitionRefreshResult {
        let snapshot = try runtime.buildRegistry(descriptorSet: descriptorData).snapshot
        let fingerprint = ContentFingerprint.sha256(of: descriptorData)

        _ = try artifactStore.writeNormalized(
            sourceID: sourceID,
            fingerprint: fingerprint,
            relativePath: "descriptor-set.pb",
            data: descriptorData
        )

        let serviceList = snapshot.allMethods.map(\.fullMethodName).joined(separator: "\n")
        _ = try artifactStore.writeNormalized(
            sourceID: sourceID,
            fingerprint: fingerprint,
            relativePath: "services.txt",
            data: Data(serviceList.utf8)
        )

        try artifactStore.writeDiagnostics(
            sourceID: sourceID,
            fingerprint: fingerprint,
            diagnostics: extraDiagnostics
        )

        return DefinitionRefreshResult(
            fingerprint: fingerprint,
            snapshotID: snapshot.id.rawValue,
            diagnostics: extraDiagnostics,
            normalizedRelativePaths: ["descriptor-set.pb", "services.txt"]
        )
    }
}
