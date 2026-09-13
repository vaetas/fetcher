import Foundation
import Observation

@MainActor
@Observable
final class RequestWorkspaceModel {
    var executionState: ExecutionState = .idle
    var protocolKind: APIProtocolKind = .rest

    var response: RESTResponseArtifact?
    var graphqlResponse: GraphQLResponseArtifact?
    var grpcResponse: GRPCResponseArtifact?

    var preview: PreparedRequestPreview?
    var lastRESTError: RESTExecutionError?
    var lastGraphQLError: GraphQLExecutionError?
    var lastGRPCError: GRPCExecutionError?
    var lastFailure: APIExecutionFailure?

    var formattedResponseBody: String?
    var responseBodyIsJSON = false
    var isFormattingResponse = false
    var isResponseBodyFullyLoaded = true
    var responseBodyNotice: String?
    var jsonFormatToken = UUID()

    var editorDiagnostics: [EditorDiagnostic] = []
    var schemaValidationBlocksSend = false

    private let registry: RequestExecutorRegistry
    private let restExecutor: RESTRequestExecutor
    private var sendTask: Task<Void, Never>?
    private var bodyFormatTask: Task<Void, Never>?
    private var validationTask: Task<Void, Never>?
    private(set) var currentRequestID: UUID?
    var draftBuilder: (() async throws -> APIRequestDraft)?

    init(
        registry: RequestExecutorRegistry? = nil,
        restExecutor: RESTRequestExecutor = RESTRequestExecutor()
    ) {
        self.restExecutor = restExecutor
        if let registry {
            self.registry = registry
        } else {
            self.registry = RequestExecutorRegistry()
            Task { @MainActor in
                await self.registry.register(restExecutor)
                await self.registry.register(GraphQLRequestExecutor())
                await self.registry.register(GRPCRequestExecutor())
            }
        }
    }

    func bind(requestID: UUID?, protocolKind: APIProtocolKind = .rest) {
        if currentRequestID != requestID {
            cancel()
            clearResponses()
            currentRequestID = requestID
        }
        self.protocolKind = protocolKind
    }

    func send() {
        guard let draftBuilder else { return }
        if schemaValidationBlocksSend {
            return
        }
        cancelInFlightOnly()
        bodyFormatTask?.cancel()
        bodyFormatTask = nil
        executionState = .running
        clearErrors()
        formattedResponseBody = nil
        isResponseBodyFullyLoaded = false
        responseBodyNotice = nil

        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                let draft = try await draftBuilder()
                let context = ExecutionContext(projectID: draft.projectID, environmentID: nil)
                self.protocolKind = draft.protocolKind

                if case .rest(let restDraft) = draft {
                    self.preview = try await self.restExecutor.preview(draft: restDraft)
                } else {
                    self.preview = nil
                }

                let result = try await self.registry.execute(draft: draft, context: context)
                guard !Task.isCancelled else {
                    self.executionState = .cancelled
                    self.lastFailure = .cancelled
                    return
                }

                switch result {
                case .rest(let artifact):
                    self.response = artifact
                    self.lastRESTError = artifact.error
                    await self.formatResponseBody(artifact)
                case .graphql(let artifact):
                    self.graphqlResponse = artifact
                    self.lastGraphQLError = artifact.error
                    if let data = artifact.dataJSON {
                        self.formattedResponseBody = data
                        self.responseBodyIsJSON = true
                        self.isResponseBodyFullyLoaded = true
                    } else if let raw = String(data: artifact.rawBody, encoding: .utf8) {
                        self.formattedResponseBody = raw
                        self.responseBodyIsJSON = false
                        self.isResponseBodyFullyLoaded = true
                    }
                case .grpc(let artifact):
                    self.grpcResponse = artifact
                    self.lastGRPCError = artifact.error
                    if let last = artifact.messages.last(where: { $0.direction == .inbound }) {
                        self.formattedResponseBody = last.json
                        self.responseBodyIsJSON = true
                        self.isResponseBodyFullyLoaded = true
                    }
                }
                self.executionState = .idle
            } catch let error as RESTExecutionError {
                self.handleRESTError(error)
            } catch let error as GraphQLExecutionError {
                self.handleGraphQLError(error)
            } catch let error as GRPCExecutionError {
                self.handleGRPCError(error)
            } catch let failure as APIExecutionFailure {
                self.lastFailure = failure
                switch failure {
                case .rest(let error): self.handleRESTError(error)
                case .graphql(let error): self.handleGraphQLError(error)
                case .grpc(let error): self.handleGRPCError(error)
                case .cancelled:
                    self.executionState = .cancelled
                case .unsupportedProtocol:
                    self.executionState = .idle
                }
            } catch is CancellationError {
                self.executionState = .cancelled
                self.lastFailure = .cancelled
            } catch {
                self.executionState = .idle
                let transport = RESTExecutionError.transport(.unknown(error.localizedDescription))
                self.lastRESTError = transport
                self.lastFailure = .rest(transport)
                self.response = self.restErrorArtifact(for: transport)
            }
        }
    }

    func cancel() {
        cancelInFlightOnly()
        if executionState == .running {
            executionState = .cancelled
            lastFailure = .cancelled
            switch protocolKind {
            case .rest:
                lastRESTError = .cancelled
                response = restErrorArtifact(for: .cancelled)
            case .graphql:
                lastGraphQLError = .cancelled
            case .grpc:
                lastGRPCError = .cancelled
            }
        }
    }

    func formatJSONBody() {
        jsonFormatToken = UUID()
    }

    func scheduleValidation(
        debounceMilliseconds: UInt64 = 200,
        work: @escaping @Sendable () async -> (diagnostics: [EditorDiagnostic], blocksSend: Bool)
    ) {
        validationTask?.cancel()
        validationTask = Task {
            try? await Task.sleep(nanoseconds: debounceMilliseconds * 1_000_000)
            guard !Task.isCancelled else { return }
            let result = await work()
            guard !Task.isCancelled else { return }
            editorDiagnostics = result.diagnostics
            schemaValidationBlocksSend = result.blocksSend
        }
    }

    private func cancelInFlightOnly() {
        sendTask?.cancel()
        sendTask = nil
    }

    private func clearResponses() {
        response = nil
        graphqlResponse = nil
        grpcResponse = nil
        preview = nil
        clearErrors()
        formattedResponseBody = nil
        responseBodyIsJSON = false
        isResponseBodyFullyLoaded = true
        responseBodyNotice = nil
        editorDiagnostics = []
        schemaValidationBlocksSend = false
        bodyFormatTask?.cancel()
        bodyFormatTask = nil
        validationTask?.cancel()
        validationTask = nil
    }

    private func clearErrors() {
        lastRESTError = nil
        lastGraphQLError = nil
        lastGRPCError = nil
        lastFailure = nil
    }

    private func handleRESTError(_ error: RESTExecutionError) {
        if case .cancelled = error {
            executionState = .cancelled
        } else {
            executionState = .idle
            response = restErrorArtifact(for: error)
        }
        lastRESTError = error
        lastFailure = .rest(error)
    }

    private func handleGraphQLError(_ error: GraphQLExecutionError) {
        if case .cancelled = error {
            executionState = .cancelled
        } else {
            executionState = .idle
        }
        lastGraphQLError = error
        lastFailure = .graphql(error)
    }

    private func handleGRPCError(_ error: GRPCExecutionError) {
        if case .cancelled = error {
            executionState = .cancelled
        } else {
            executionState = .idle
        }
        lastGRPCError = error
        lastFailure = .grpc(error)
    }

    private func formatResponseBody(_ artifact: RESTResponseArtifact) async {
        bodyFormatTask?.cancel()
        let data = artifact.body
        let mime = artifact.mimeType

        isFormattingResponse = true
        isResponseBodyFullyLoaded = false
        responseBodyNotice = nil
        formattedResponseBody = nil
        responseBodyIsJSON = false

        bodyFormatTask = Task {
            await ResponseBodyFormatter.loadProgressively(data: data, mimeType: mime) { update in
                switch update {
                case .replace(let text, let isJSON, let isComplete, let notice):
                    formattedResponseBody = text
                    responseBodyIsJSON = isJSON
                    isResponseBodyFullyLoaded = isComplete
                    responseBodyNotice = notice
                    isFormattingResponse = !isComplete
                case .append(let text, let isComplete, let notice):
                    formattedResponseBody = (formattedResponseBody ?? "") + text
                    isResponseBodyFullyLoaded = isComplete
                    if let notice { responseBodyNotice = notice }
                    isFormattingResponse = !isComplete
                }
            }
        }

        await bodyFormatTask?.value
        if isFormattingResponse, isResponseBodyFullyLoaded {
            isFormattingResponse = false
        }
    }

    private func restErrorArtifact(for error: RESTExecutionError) -> RESTResponseArtifact {
        RESTResponseArtifact(
            id: UUID(),
            requestID: currentRequestID ?? UUID(),
            startedAt: .now,
            finishedAt: .now,
            originalURL: URL(string: "about:blank")!,
            finalURL: nil,
            statusCode: nil,
            headers: [],
            body: Data(),
            mimeType: nil,
            textEncodingName: nil,
            expectedContentLength: nil,
            metrics: nil,
            redirects: [],
            error: error
        )
    }
}

extension RequestWorkspaceModel {
    /// Compatibility for REST-only response UI.
    var lastError: RESTExecutionError? { lastRESTError }
}
