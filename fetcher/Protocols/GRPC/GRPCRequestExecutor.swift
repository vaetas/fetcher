import Foundation

protocol GRPCSchemaProviding: Sendable {
    func snapshot(for sourceID: DefinitionSourceID) async throws -> ProtobufSchemaSnapshot?
}

struct EmptyGRPCSchemaProvider: GRPCSchemaProviding {
    func snapshot(for sourceID: DefinitionSourceID) async throws -> ProtobufSchemaSnapshot? {
        nil
    }
}

struct CachingGRPCSchemaProvider: GRPCSchemaProviding, Sendable {
    private let artifactStore: SchemaArtifactStore
    private let runtime: any DynamicProtobufRuntime
    private let fingerprintLookup: @Sendable (DefinitionSourceID) async -> String?

    init(
        artifactStore: SchemaArtifactStore,
        runtime: any DynamicProtobufRuntime = BuiltinDynamicProtobufRuntime(),
        fingerprintLookup: @escaping @Sendable (DefinitionSourceID) async -> String? = { _ in nil }
    ) {
        self.artifactStore = artifactStore
        self.runtime = runtime
        self.fingerprintLookup = fingerprintLookup
    }

    func snapshot(for sourceID: DefinitionSourceID) async throws -> ProtobufSchemaSnapshot? {
        guard let fingerprint = await fingerprintLookup(sourceID) else {
            return nil
        }
        let data = try artifactStore.readNormalized(
            sourceID: sourceID.rawValue,
            fingerprint: fingerprint,
            relativePath: "descriptor-set.pb"
        )
        return try runtime.buildRegistry(descriptorSet: data).snapshot
    }
}

struct GRPCRequestExecutor: APIRequestExecutor {
    let kind: APIProtocolKind = .grpc

    private let invoker: GRPCDynamicInvoker
    private let runtime: any DynamicProtobufRuntime
    private let schemaProvider: any GRPCSchemaProviding
    private let transport: any DynamicGRPCTransport

    init(
        invoker: GRPCDynamicInvoker? = nil,
        runtime: any DynamicProtobufRuntime = BuiltinDynamicProtobufRuntime(),
        schemaProvider: any GRPCSchemaProviding = EmptyGRPCSchemaProvider(),
        transport: any DynamicGRPCTransport = CompositeDynamicGRPCTransport()
    ) {
        self.runtime = runtime
        self.transport = transport
        self.invoker = invoker ?? GRPCDynamicInvoker(runtime: runtime, transport: transport)
        self.schemaProvider = schemaProvider
    }

    func execute(
        draft: APIRequestDraft,
        context: ExecutionContext
    ) async throws -> APIExecutionResult {
        guard case .grpc(let grpcDraft) = draft else {
            throw APIExecutionFailure.unsupportedProtocol(draft.protocolKind)
        }
        return try await execute(draft: grpcDraft, context: context)
    }

    func execute(
        draft: GRPCRequestDraft,
        context: ExecutionContext
    ) async throws -> APIExecutionResult {
        let startedAt = Date()
        let resolvedTarget = resolveVariables(in: draft.target, variables: draft.variables, secrets: draft.secretVariables)

        guard let snapshot = try await schemaProvider.snapshot(for: draft.definitionSourceID) else {
            throw APIExecutionFailure.grpc(.schemaUnavailable("Attach and refresh a protobuf API definition before sending."))
        }

        let registry = ProtobufRegistry(snapshot: snapshot)
        guard let method = snapshot.method(serviceFullName: draft.serviceFullName, methodName: draft.methodName) else {
            throw APIExecutionFailure.grpc(.unknownMethod("\(draft.serviceFullName)/\(draft.methodName)"))
        }

        let metadata = draft.metadata
            .filter(\.isEnabled)
            .filter { !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { ($0.key, resolveVariables(in: $0.value, variables: draft.variables, secrets: draft.secretVariables)) }

        let deadline = draft.deadline.map { Date().addingTimeInterval($0.seconds) }

        switch method.callShape {
        case .unary:
            return try await executeUnary(
                draft: draft,
                target: resolvedTarget,
                method: method,
                registry: registry,
                metadata: metadata,
                deadline: deadline,
                startedAt: startedAt
            )
        case .serverStreaming, .clientStreaming, .bidirectionalStreaming:
            return try await executeStreaming(
                draft: draft,
                target: resolvedTarget,
                method: method,
                registry: registry,
                metadata: metadata,
                deadline: deadline,
                startedAt: startedAt
            )
        }
    }

    private func executeUnary(
        draft: GRPCRequestDraft,
        target: String,
        method: ProtoMethodDescriptor,
        registry: ProtobufRegistry,
        metadata: [(String, String)],
        deadline: Date?,
        startedAt: Date
    ) async throws -> APIExecutionResult {
        let bodyJSON = draft.bodyJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : draft.bodyJSON
        let validationIssues = runtime.validateJSON(bodyJSON, messageType: method.inputType, registry: registry)
        if let issue = validationIssues.first {
            throw APIExecutionFailure.grpc(.invalidMessageJSON(issue.message))
        }

        let result = try await invoker.unary(
            target: target,
            serviceFullName: draft.serviceFullName,
            methodName: draft.methodName,
            requestJSON: bodyJSON,
            inputType: method.inputType,
            outputType: method.outputType,
            registry: registry,
            metadata: metadata,
            tls: draft.tls,
            authorityOverride: draft.authorityOverride,
            deadline: deadline,
            requestCompression: draft.requestCompression
        )

        let finishedAt = Date()
        let artifact = GRPCResponseArtifact(
            id: UUID(),
            requestID: draft.requestID,
            startedAt: startedAt,
            finishedAt: finishedAt,
            target: target,
            serviceFullName: draft.serviceFullName,
            methodName: draft.methodName,
            callShape: .unary,
            streamState: .completed,
            initialMetadata: result.initialMetadata,
            trailingMetadata: result.trailers,
            messages: [
                GRPCMessageEvent(sequence: 1, direction: .inbound, json: result.messageJSON)
            ],
            status: result.status,
            metrics: RequestMetrics(
                totalDuration: finishedAt.timeIntervalSince(startedAt),
                redirectCount: 0
            ),
            error: nil
        )
        return .grpc(artifact)
    }

    private func executeStreaming(
        draft: GRPCRequestDraft,
        target: String,
        method: ProtoMethodDescriptor,
        registry: ProtobufRegistry,
        metadata: [(String, String)],
        deadline: Date?,
        startedAt: Date
    ) async throws -> APIExecutionResult {
        let endpoint = try parseTargetForStreaming(target, tls: draft.tls)
        let key = GRPCChannelKey(
            host: endpoint.host,
            port: endpoint.port,
            useTLS: draft.tls.useTLS,
            authority: draft.authorityOverride ?? draft.tls.authorityOverride
        )
        let path = "/\(draft.serviceFullName)/\(draft.methodName)"

        let session = GRPCStreamSession()
        let outboundJSON = draft.outboundMessagesJSON.isEmpty ? [draft.bodyJSON] : draft.outboundMessagesJSON

        for json in outboundJSON {
            let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : json
            let issues = runtime.validateJSON(trimmed, messageType: method.inputType, registry: registry)
            if let issue = issues.first {
                throw APIExecutionFailure.grpc(.invalidMessageJSON(issue.message))
            }
        }

        switch method.callShape {
        case .serverStreaming:
            let requestJSON = outboundJSON.first ?? "{}"
            let requestBytes = try runtime.encodeProtoJSON(requestJSON, messageType: method.inputType, registry: registry)
            let stream = try await transport.serverStreamingCall(
                key: key,
                path: path,
                requestBytes: requestBytes,
                metadata: metadata,
                deadline: deadline,
                requestCompression: draft.requestCompression
            )
            await session.configure(
                send: { _ in },
                halfClose: { },
                cancel: { },
                receive: { stream }
            )
            await session.waitForCompletion()
            let messages = await decodeInboundStream(session: session, outputType: method.outputType, registry: registry)
            return makeStreamingArtifact(
                draft: draft,
                target: target,
                method: method,
                startedAt: startedAt,
                messages: messages,
                streamState: .completed
            )

        case .clientStreaming, .bidirectionalStreaming:
            let handle: DynamicGRPCClientStreamHandle
            switch method.callShape {
            case .clientStreaming:
                handle = try await transport.clientStreamingCall(
                    key: key,
                    path: path,
                    metadata: metadata,
                    deadline: deadline,
                    requestCompression: draft.requestCompression
                )
            case .bidirectionalStreaming:
                handle = try await transport.bidirectionalStreamingCall(
                    key: key,
                    path: path,
                    metadata: metadata,
                    deadline: deadline,
                    requestCompression: draft.requestCompression
                )
            default:
                throw GRPCExecutionError.transport("Unexpected streaming shape.")
            }

            await session.configure(
                send: handle.send,
                halfClose: handle.halfClose,
                cancel: handle.cancel,
                receive: handle.receive
            )

            for json in outboundJSON {
                let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : json
                let bytes = try runtime.encodeProtoJSON(trimmed, messageType: method.inputType, registry: registry)
                try await session.send(messageJSON: trimmed, encodedBytes: bytes)
            }
            try await session.halfClose()
            await session.waitForCompletion()

            let messages = await decodeInboundStream(session: session, outputType: method.outputType, registry: registry)
            return makeStreamingArtifact(
                draft: draft,
                target: target,
                method: method,
                startedAt: startedAt,
                messages: messages,
                streamState: await session.state
            )

        case .unary:
            throw GRPCExecutionError.transport("Unexpected unary shape in streaming executor.")
        }
    }

    private func decodeInboundStream(
        session: GRPCStreamSession,
        outputType: ProtobufTypeID,
        registry: ProtobufRegistry
    ) async -> [GRPCMessageEvent] {
        let inbound = await session.inboundMessages
        return inbound.enumerated().map { index, event in
            let decoded: String
            if let data = event.json.data(using: .utf8),
               let text = try? runtime.decodeToProtoJSON(data, messageType: outputType, registry: registry) {
                decoded = text
            } else {
                decoded = event.json
            }
            return GRPCMessageEvent(
                id: event.id,
                sequence: index + 1,
                arrivedAt: event.arrivedAt,
                direction: .inbound,
                json: decoded
            )
        }
    }

    private func makeStreamingArtifact(
        draft: GRPCRequestDraft,
        target: String,
        method: ProtoMethodDescriptor,
        startedAt: Date,
        messages: [GRPCMessageEvent],
        streamState: GRPCStreamState
    ) -> APIExecutionResult {
        let finishedAt = Date()
        let artifact = GRPCResponseArtifact(
            id: UUID(),
            requestID: draft.requestID,
            startedAt: startedAt,
            finishedAt: finishedAt,
            target: target,
            serviceFullName: draft.serviceFullName,
            methodName: draft.methodName,
            callShape: method.callShape,
            streamState: streamState,
            initialMetadata: [],
            trailingMetadata: [],
            messages: messages,
            status: streamState == .completed ? .ok : nil,
            metrics: RequestMetrics(
                totalDuration: finishedAt.timeIntervalSince(startedAt),
                redirectCount: 0
            ),
            error: nil
        )
        return .grpc(artifact)
    }

    private struct ParsedTarget {
        var host: String
        var port: Int
    }

    private func parseTargetForStreaming(_ target: String, tls: GRPCTLSConfiguration) throws -> ParsedTarget {
        if target.hasPrefix("mock://") {
            return ParsedTarget(host: "mock", port: 0)
        }
        var work = target.trimmingCharacters(in: .whitespacesAndNewlines)
        if !work.contains("://") {
            work = (tls.useTLS ? "grpcs://" : "grpc://") + work
        }
        guard let url = URL(string: work), let host = url.host else {
            throw GRPCExecutionError.invalidTarget("Unable to parse gRPC target '\(target)'.")
        }
        let defaultPort = tls.useTLS ? 443 : 80
        return ParsedTarget(host: host, port: url.port ?? defaultPort)
    }

    private func resolveVariables(in template: String, variables: [String: String], secrets: [String: String]) -> String {
        var result = template
        let merged = variables.merging(secrets) { _, secret in secret }
        for (key, value) in merged {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return result
    }
}
