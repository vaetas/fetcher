import CryptoKit
import Foundation

enum ContentFingerprint {
    static func sha256(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(of string: String) -> String {
        sha256(of: Data(string.utf8))
    }
}

enum SchemaResourceLimits {
    static let maxFileCount = 2_000
    static let maxIndividualFileBytes = 8 * 1024 * 1024
    static let maxTotalSourceBytes = 64 * 1024 * 1024
    static let maxNestingDepth = 64
    static let maxRemoteRedirects = 5
    static let maxGraphQLSDLBytes = 16 * 1024 * 1024
    static let maxGraphQLTypeCount = 50_000
    static let maxProtobufDescriptorCount = 50_000
    static let schemaRefreshTimeout: TimeInterval = 60
    static let maxStreamingMessagesRetained = 5_000
    static let maxSampleGenerationDepth = 4
}

struct SchemaSnapshotMetadata: Codable, Sendable, Equatable {
    var id: UUID
    var fingerprint: String
    var createdAt: Date
    var sourceKind: String
    var diagnosticsJSON: String?
}

final class SchemaArtifactStore: @unchecked Sendable {
    private let rootURL: URL
    private let fileManager: FileManager

    init(
        fileManager: FileManager = .default,
        applicationSupportSubdirectory: String = "APIDefinitions"
    ) throws {
        self.fileManager = fileManager
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.pavlovsky.fetcher"
        rootURL = base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent(applicationSupportSubdirectory, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func snapshotDirectory(sourceID: UUID, fingerprint: String) -> URL {
        rootURL
            .appendingPathComponent(sourceID.uuidString, isDirectory: true)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(fingerprint, isDirectory: true)
    }

    func prepareSnapshotDirectory(sourceID: UUID, fingerprint: String) throws -> URL {
        let directory = snapshotDirectory(sourceID: sourceID, fingerprint: fingerprint)
        try fileManager.createDirectory(at: directory.appendingPathComponent("source", isDirectory: true), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: directory.appendingPathComponent("normalized", isDirectory: true), withIntermediateDirectories: true)
        return directory
    }

    func writeNormalized(
        sourceID: UUID,
        fingerprint: String,
        relativePath: String,
        data: Data
    ) throws -> URL {
        let directory = try prepareSnapshotDirectory(sourceID: sourceID, fingerprint: fingerprint)
        let url = directory.appendingPathComponent("normalized", isDirectory: true).appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    func writeDiagnostics(
        sourceID: UUID,
        fingerprint: String,
        diagnostics: [EditorDiagnostic]
    ) throws {
        let directory = try prepareSnapshotDirectory(sourceID: sourceID, fingerprint: fingerprint)
        let payload = try JSONEncoder().encode(diagnostics.map(PersistedDiagnostic.init))
        try payload.write(to: directory.appendingPathComponent("diagnostics.json"), options: .atomic)
    }

    func readNormalized(sourceID: UUID, fingerprint: String, relativePath: String) throws -> Data {
        let url = snapshotDirectory(sourceID: sourceID, fingerprint: fingerprint)
            .appendingPathComponent("normalized", isDirectory: true)
            .appendingPathComponent(relativePath)
        return try Data(contentsOf: url)
    }

    func removeSource(sourceID: UUID) throws {
        let url = rootURL.appendingPathComponent(sourceID.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private struct PersistedDiagnostic: Codable {
        var severity: String
        var message: String
        var location: Int?
        var length: Int?
        var source: String?

        init(_ diagnostic: EditorDiagnostic) {
            severity = diagnostic.severity.rawValue
            message = diagnostic.message
            location = diagnostic.range?.location
            length = diagnostic.range?.length
            source = diagnostic.source
        }
    }
}

struct SecurityScopedBookmarkStore: Sendable {
    func makeBookmark(for url: URL) throws -> Data {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        return try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    func withAccessing<T>(bookmark: Data, _ body: (URL) throws -> T) throws -> T {
        let resolved = try resolveBookmark(bookmark)
        let accessing = resolved.url.startAccessingSecurityScopedResource()
        defer {
            if accessing { resolved.url.stopAccessingSecurityScopedResource() }
        }
        return try body(resolved.url)
    }

    func withAccessing<T>(bookmarks: [Data], _ body: ([URL]) throws -> T) throws -> T {
        let resolved = try bookmarks.map(resolveBookmark)
        let accesses = resolved.map { $0.url.startAccessingSecurityScopedResource() }
        defer {
            for (index, resolvedURL) in resolved.enumerated().reversed() where accesses[index] {
                resolvedURL.url.stopAccessingSecurityScopedResource()
            }
        }
        return try body(resolved.map(\.url))
    }
}
