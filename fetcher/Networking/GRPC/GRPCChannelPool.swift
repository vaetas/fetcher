import Foundation

struct GRPCChannelKey: Hashable, Sendable {
    let host: String
    let port: Int
    let useTLS: Bool
    let authority: String?

    init(host: String, port: Int, useTLS: Bool, authority: String? = nil) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.authority = authority
    }
}

protocol DynamicGRPCTransport: Sendable {
    func unaryCall(
        key: GRPCChannelKey,
        path: String,
        requestBytes: Data,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> DynamicGRPCUnaryResponse

    func serverStreamingCall(
        key: GRPCChannelKey,
        path: String,
        requestBytes: Data,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> AsyncThrowingStream<Data, Error>

    func clientStreamingCall(
        key: GRPCChannelKey,
        path: String,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> DynamicGRPCClientStreamHandle

    func bidirectionalStreamingCall(
        key: GRPCChannelKey,
        path: String,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> DynamicGRPCClientStreamHandle
}

struct DynamicGRPCUnaryResponse: Sendable {
    var messageBytes: Data
    var initialMetadata: [(String, String)]
    var trailingMetadata: [(String, String)]
    var status: GRPCStatus
}

struct DynamicGRPCClientStreamHandle: Sendable {
    let send: @Sendable (Data) async throws -> Void
    let halfClose: @Sendable () async throws -> Void
    let receive: @Sendable () async throws -> AsyncThrowingStream<Data, Error>
    let cancel: @Sendable () -> Void
}

actor GRPCChannelPool {
    private struct Entry {
        let key: GRPCChannelKey
        let createdAt: Date
        var lastUsedAt: Date
    }

    private let transport: any DynamicGRPCTransport
    private var entries: [GRPCChannelKey: Entry] = [:]
    private let idleEvictionInterval: TimeInterval = 300

    init(transport: any DynamicGRPCTransport) {
        self.transport = transport
    }

    func transport(for key: GRPCChannelKey) -> any DynamicGRPCTransport {
        entries[key] = Entry(
            key: key,
            createdAt: entries[key]?.createdAt ?? .now,
            lastUsedAt: .now
        )
        evictIdleChannels()
        return transport
    }

    func remove(key: GRPCChannelKey) {
        entries.removeValue(forKey: key)
    }

    func removeAll() {
        entries.removeAll()
    }

    private func evictIdleChannels() {
        let cutoff = Date().addingTimeInterval(-idleEvictionInterval)
        entries = entries.filter { _, entry in entry.lastUsedAt >= cutoff }
    }
}
