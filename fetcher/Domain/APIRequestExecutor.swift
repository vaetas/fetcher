import Foundation

protocol APIRequestExecutor: Sendable {
    var kind: APIProtocolKind { get }

    func execute(
        draft: APIRequestDraft,
        context: ExecutionContext
    ) async throws -> APIExecutionResult
}

actor RequestExecutorRegistry {
    private var executors: [APIProtocolKind: any APIRequestExecutor]

    init(executors: [APIProtocolKind: any APIRequestExecutor] = [:]) {
        self.executors = executors
    }

    func register(_ executor: any APIRequestExecutor) {
        executors[executor.kind] = executor
    }

    func executor(for kind: APIProtocolKind) -> (any APIRequestExecutor)? {
        executors[kind]
    }

    func execute(
        draft: APIRequestDraft,
        context: ExecutionContext
    ) async throws -> APIExecutionResult {
        guard let executor = executors[draft.protocolKind] else {
            throw APIExecutionFailure.unsupportedProtocol(draft.protocolKind)
        }
        return try await executor.execute(draft: draft, context: context)
    }
}

enum RequestExecutorRegistryFactory {
    static func makeDefault() -> RequestExecutorRegistry {
        let registry = RequestExecutorRegistry()
        Task {
            await registry.register(RESTRequestExecutor())
            await registry.register(GraphQLRequestExecutor())
            await registry.register(GRPCRequestExecutor())
        }
        return registry
    }

    static func makeDefaultSync() async -> RequestExecutorRegistry {
        let registry = RequestExecutorRegistry()
        await registry.register(RESTRequestExecutor())
        await registry.register(GraphQLRequestExecutor())
        await registry.register(GRPCRequestExecutor())
        return registry
    }
}

final class RequestExecutionHandle: @unchecked Sendable {
    let id: UUID
    private let onCancel: @Sendable () -> Void

    init(id: UUID = UUID(), onCancel: @escaping @Sendable () -> Void) {
        self.id = id
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel()
    }
}
