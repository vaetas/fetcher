import Foundation

struct DefinitionRefreshResult: Sendable {
    var fingerprint: String
    var snapshotID: UUID
    var diagnostics: [EditorDiagnostic]
    var normalizedRelativePaths: [String]
}

protocol DefinitionLoader: Sendable {
    var kind: APIDefinitionKind { get }
    func refresh(
        sourceID: UUID,
        configData: Data,
        artifactStore: SchemaArtifactStore
    ) async throws -> DefinitionRefreshResult
}

actor DefinitionRefreshCoordinator {
    private let artifactStore: SchemaArtifactStore
    private var loaders: [APIDefinitionKind: any DefinitionLoader]
    private var inFlight: [UUID: Task<DefinitionRefreshResult, Error>] = [:]

    init(
        artifactStore: SchemaArtifactStore,
        loaders: [APIDefinitionKind: any DefinitionLoader] = [:]
    ) {
        self.artifactStore = artifactStore
        self.loaders = loaders
    }

    func register(_ loader: any DefinitionLoader) {
        loaders[loader.kind] = loader
    }

    func refresh(
        sourceID: UUID,
        kind: APIDefinitionKind,
        configData: Data
    ) async throws -> DefinitionRefreshResult {
        if let existing = inFlight[sourceID] {
            return try await existing.value
        }

        guard let loader = loaders[kind] else {
            throw DefinitionRefreshError.noLoader(kind)
        }

        let task = Task {
            try await loader.refresh(
                sourceID: sourceID,
                configData: configData,
                artifactStore: artifactStore
            )
        }
        inFlight[sourceID] = task
        defer { inFlight[sourceID] = nil }

        do {
            return try await task.value
        } catch is CancellationError {
            throw DefinitionRefreshError.cancelled
        }
    }

    func cancel(sourceID: UUID) {
        inFlight[sourceID]?.cancel()
        inFlight[sourceID] = nil
    }
}

enum DefinitionRefreshError: Error, Sendable, Equatable {
    case noLoader(APIDefinitionKind)
    case cancelled
    case invalidConfiguration(String)
    case sourceUnavailable(String)
    case limitExceeded(String)
    case compilationFailed(String)

    var message: String {
        switch self {
        case .noLoader(let kind):
            return "No loader registered for \(kind.displayName)."
        case .cancelled:
            return "Definition refresh was cancelled."
        case .invalidConfiguration(let detail),
             .sourceUnavailable(let detail),
             .limitExceeded(let detail),
             .compilationFailed(let detail):
            return detail
        }
    }
}
