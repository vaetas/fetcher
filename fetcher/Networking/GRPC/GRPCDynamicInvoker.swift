import Foundation
import Network

struct DynamicGRPCMessage: Sendable {
    var serializedBytes: Data
}

struct GRPCDynamicInvoker: Sendable {
    private let runtime: any DynamicProtobufRuntime
    private let channelPool: GRPCChannelPool
    private let transport: any DynamicGRPCTransport

    init(
        runtime: any DynamicProtobufRuntime = BuiltinDynamicProtobufRuntime(),
        transport: any DynamicGRPCTransport = CompositeDynamicGRPCTransport()
    ) {
        self.runtime = runtime
        self.transport = transport
        self.channelPool = GRPCChannelPool(transport: transport)
    }

    func unary(
        target: String,
        serviceFullName: String,
        methodName: String,
        requestJSON: String,
        inputType: ProtobufTypeID,
        outputType: ProtobufTypeID,
        registry: ProtobufRegistry,
        metadata: [(String, String)] = [],
        tls: GRPCTLSConfiguration = .plaintext,
        authorityOverride: String? = nil,
        deadline: Date? = nil,
        requestCompression: GRPCCompressionPreference? = nil
    ) async throws -> (
        messageJSON: String,
        initialMetadata: [(String, String)],
        trailers: [(String, String)],
        status: GRPCStatus
    ) {
        let requestBytes = try runtime.encodeProtoJSON(requestJSON, messageType: inputType, registry: registry)
        let path = "/\(serviceFullName)/\(methodName)"

        if target.hasPrefix("mock://") {
            let responseJSON = try mockResponseJSON(for: outputType, registry: registry)
            return (
                messageJSON: responseJSON,
                initialMetadata: [("content-type", "application/grpc")],
                trailers: [("grpc-status", "0"), ("grpc-message", "")],
                status: .ok
            )
        }

        let endpoint = try parseTarget(target, tls: tls)
        let key = GRPCChannelKey(
            host: endpoint.host,
            port: endpoint.port,
            useTLS: tls.useTLS,
            authority: authorityOverride ?? tls.authorityOverride
        )

        let activeTransport = await channelPool.transport(for: key)
        let response = try await activeTransport.unaryCall(
            key: key,
            path: path,
            requestBytes: requestBytes,
            metadata: metadata,
            deadline: deadline,
            requestCompression: requestCompression
        )

        let messageJSON = try runtime.decodeToProtoJSON(
            response.messageBytes,
            messageType: outputType,
            registry: registry
        )

        return (
            messageJSON: messageJSON,
            initialMetadata: response.initialMetadata,
            trailers: response.trailingMetadata,
            status: response.status
        )
    }

    private func mockResponseJSON(for outputType: ProtobufTypeID, registry: ProtobufRegistry) throws -> String {
        if registry.snapshot.messagesByName[outputType.fullName] != nil {
            return "{}"
        }
        return "{}"
    }

    private struct ParsedTarget {
        var host: String
        var port: Int
    }

    private func parseTarget(_ target: String, tls: GRPCTLSConfiguration) throws -> ParsedTarget {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GRPCExecutionError.invalidTarget("Target is empty.")
        }

        if trimmed.hasPrefix("mock://") {
            return ParsedTarget(host: "mock", port: 0)
        }

        var work = trimmed
        if !work.contains("://") {
            work = (tls.useTLS ? "grpcs://" : "grpc://") + work
        }

        guard let url = URL(string: work), let host = url.host else {
            throw GRPCExecutionError.invalidTarget("Unable to parse gRPC target '\(target)'.")
        }

        let defaultPort = tls.useTLS ? 443 : 80
        let port = url.port ?? defaultPort
        return ParsedTarget(host: host, port: port)
    }
}

struct CompositeDynamicGRPCTransport: DynamicGRPCTransport {
    private let mockTransport = MockGRPCTransport()
    private let nwTransport = NWGRPCUnaryTransport()

    func unaryCall(
        key: GRPCChannelKey,
        path: String,
        requestBytes: Data,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> DynamicGRPCUnaryResponse {
        if key.host == "mock" {
            return try await mockTransport.unaryCall(
                key: key,
                path: path,
                requestBytes: requestBytes,
                metadata: metadata,
                deadline: deadline,
                requestCompression: requestCompression
            )
        }
        return try await nwTransport.unaryCall(
            key: key,
            path: path,
            requestBytes: requestBytes,
            metadata: metadata,
            deadline: deadline,
            requestCompression: requestCompression
        )
    }

    func serverStreamingCall(
        key: GRPCChannelKey,
        path: String,
        requestBytes: Data,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> AsyncThrowingStream<Data, Error> {
        if key.host == "mock" {
            return try await mockTransport.serverStreamingCall(
                key: key,
                path: path,
                requestBytes: requestBytes,
                metadata: metadata,
                deadline: deadline,
                requestCompression: requestCompression
            )
        }
        throw GRPCExecutionError.transport("Server streaming requires grpc-swift-2 adapter (not yet connected).")
    }

    func clientStreamingCall(
        key: GRPCChannelKey,
        path: String,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> DynamicGRPCClientStreamHandle {
        if key.host == "mock" {
            return try await mockTransport.clientStreamingCall(
                key: key,
                path: path,
                metadata: metadata,
                deadline: deadline,
                requestCompression: requestCompression
            )
        }
        throw GRPCExecutionError.transport("Client streaming requires grpc-swift-2 adapter (not yet connected).")
    }

    func bidirectionalStreamingCall(
        key: GRPCChannelKey,
        path: String,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> DynamicGRPCClientStreamHandle {
        if key.host == "mock" {
            return try await mockTransport.bidirectionalStreamingCall(
                key: key,
                path: path,
                metadata: metadata,
                deadline: deadline,
                requestCompression: requestCompression
            )
        }
        throw GRPCExecutionError.transport("Bidirectional streaming requires grpc-swift-2 adapter (not yet connected).")
    }
}

struct MockGRPCTransport: DynamicGRPCTransport {
    func unaryCall(
        key: GRPCChannelKey,
        path: String,
        requestBytes: Data,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> DynamicGRPCUnaryResponse {
        DynamicGRPCUnaryResponse(
            messageBytes: Data(),
            initialMetadata: [("content-type", "application/grpc")],
            trailingMetadata: [("grpc-status", "0")],
            status: .ok
        )
    }

    func serverStreamingCall(
        key: GRPCChannelKey,
        path: String,
        requestBytes: Data,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(Data())
            continuation.finish()
        }
    }

    func clientStreamingCall(
        key: GRPCChannelKey,
        path: String,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> DynamicGRPCClientStreamHandle {
        DynamicGRPCClientStreamHandle(
            send: { _ in },
            halfClose: { },
            receive: {
                AsyncThrowingStream { continuation in
                    continuation.yield(Data())
                    continuation.finish()
                }
            },
            cancel: { }
        )
    }

    func bidirectionalStreamingCall(
        key: GRPCChannelKey,
        path: String,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> DynamicGRPCClientStreamHandle {
        try await clientStreamingCall(
            key: key,
            path: path,
            metadata: metadata,
            deadline: deadline,
            requestCompression: requestCompression
        )
    }
}

struct NWGRPCUnaryTransport: DynamicGRPCTransport {
    func unaryCall(
        key: GRPCChannelKey,
        path: String,
        requestBytes: Data,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> DynamicGRPCUnaryResponse {
        if key.useTLS {
            throw GRPCExecutionError.transport("TLS gRPC transport requires grpc-swift-2 adapter (not yet connected).")
        }

        let host = NWEndpoint.Host(key.host)
        let port = NWEndpoint.Port(rawValue: UInt16(clamping: key.port)) ?? .http
        let connection = NWConnection(host: host, port: port, using: .tcp)
        connection.start(queue: .global(qos: .userInitiated))

        defer { connection.cancel() }

        try await waitForReady(connection: connection, deadline: deadline)

        let requestFrame = try buildGRPCRequestFrame(path: path, message: requestBytes, metadata: metadata, authority: key.authority)
        try await send(connection: connection, data: requestFrame)

        let responseBytes = try await readGRPCResponse(connection: connection, deadline: deadline)
        let parsed = try parseGRPCResponseFrames(responseBytes)

        if parsed.status.code != 0 {
            throw GRPCExecutionError.status(parsed.status)
        }

        return DynamicGRPCUnaryResponse(
            messageBytes: parsed.message,
            initialMetadata: parsed.initialMetadata,
            trailingMetadata: parsed.trailingMetadata,
            status: parsed.status
        )
    }

    func serverStreamingCall(
        key: GRPCChannelKey,
        path: String,
        requestBytes: Data,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> AsyncThrowingStream<Data, Error> {
        throw GRPCExecutionError.transport("Server streaming over NWConnection is not yet implemented.")
    }

    func clientStreamingCall(
        key: GRPCChannelKey,
        path: String,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> DynamicGRPCClientStreamHandle {
        throw GRPCExecutionError.transport("Client streaming over NWConnection is not yet implemented.")
    }

    func bidirectionalStreamingCall(
        key: GRPCChannelKey,
        path: String,
        metadata: [(String, String)],
        deadline: Date?,
        requestCompression: GRPCCompressionPreference?
    ) async throws -> DynamicGRPCClientStreamHandle {
        throw GRPCExecutionError.transport("Bidirectional streaming over NWConnection is not yet implemented.")
    }

    private struct ParsedResponse {
        var message: Data
        var initialMetadata: [(String, String)]
        var trailingMetadata: [(String, String)]
        var status: GRPCStatus
    }

    private func waitForReady(connection: NWConnection, deadline: Date?) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: GRPCExecutionError.transport(error.localizedDescription))
                case .cancelled:
                    continuation.resume(throwing: GRPCExecutionError.cancelled)
                default:
                    break
                }
            }
            if let deadline, deadline < .now {
                continuation.resume(throwing: GRPCExecutionError.timeout)
            }
        }
    }

    private func send(connection: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: GRPCExecutionError.transport(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func readGRPCResponse(connection: NWConnection, deadline: Date?) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, _, error in
                if let error {
                    continuation.resume(throwing: GRPCExecutionError.transport(error.localizedDescription))
                    return
                }
                continuation.resume(returning: content ?? Data())
            }
        }
    }

    private func buildGRPCRequestFrame(
        path: String,
        message: Data,
        metadata: [(String, String)],
        authority: String?
    ) throws -> Data {
        var headers = """
        POST \(path) HTTP/2.0\r
        te: trailers\r
        content-type: application/grpc\r
        user-agent: fetcher-grpc/1.0\r
        """
        if let authority, !authority.isEmpty {
            headers += "\r\n:authority: \(authority)"
        }
        for (key, value) in metadata where !key.isEmpty {
            headers += "\r\n\(key): \(value)"
        }
        headers += "\r\n\r\n"

        var frame = Data(headers.utf8)
        var grpcMessage = Data([0])
        var length = UInt32(message.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(message)
        _ = grpcMessage
        return frame
    }

    private func parseGRPCResponseFrames(_ data: Data) throws -> ParsedResponse {
        guard data.count >= 5 else {
            return ParsedResponse(
                message: Data(),
                initialMetadata: [],
                trailingMetadata: [],
                status: GRPCStatus(code: 14, message: "gRPC transport not yet connected (HTTP/2 framing incomplete)")
            )
        }

        let compressionFlag = data[data.startIndex]
        let lengthData = data.subdata(in: 1 ..< 5)
        let messageLength = lengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let messageStart = 5
        let messageEnd = messageStart + Int(messageLength)
        guard messageEnd <= data.count else {
            throw GRPCExecutionError.transport("Incomplete gRPC message frame.")
        }
        let message = data.subdata(in: messageStart ..< messageEnd)
        _ = compressionFlag
        return ParsedResponse(
            message: message,
            initialMetadata: [],
            trailingMetadata: [],
            status: .ok
        )
    }
}
