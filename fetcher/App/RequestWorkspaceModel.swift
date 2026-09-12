import Foundation
import Observation

@MainActor
@Observable
final class RequestWorkspaceModel {
    var executionState: ExecutionState = .idle
    var response: RESTResponseArtifact?
    var preview: PreparedRequestPreview?
    var lastError: RESTExecutionError?
    var formattedResponseBody: String?
    var responseBodyIsJSON = false
    var isFormattingResponse = false
    var isResponseBodyFullyLoaded = true
    var responseBodyNotice: String?
    var jsonFormatToken = UUID()

    private let executor: RESTRequestExecutor
    private var sendTask: Task<Void, Never>?
    private var bodyFormatTask: Task<Void, Never>?
    private(set) var currentRequestID: UUID?
    var draftBuilder: (() async throws -> RESTRequestDraft)?

    init(executor: RESTRequestExecutor = RESTRequestExecutor()) {
        self.executor = executor
    }

    func bind(requestID: UUID?) {
        if currentRequestID != requestID {
            cancel()
            response = nil
            preview = nil
            lastError = nil
            formattedResponseBody = nil
            responseBodyIsJSON = false
            isResponseBodyFullyLoaded = true
            responseBodyNotice = nil
            bodyFormatTask?.cancel()
            bodyFormatTask = nil
            currentRequestID = requestID
        }
    }

    func send() {
        guard let draftBuilder else { return }
        cancelInFlightOnly()
        bodyFormatTask?.cancel()
        bodyFormatTask = nil
        executionState = .running
        lastError = nil
        formattedResponseBody = nil
        isResponseBodyFullyLoaded = false
        responseBodyNotice = nil
        sendTask = Task { [weak self] in
            guard let self else { return }
            do {
                let draft = try await draftBuilder()
                let context = ExecutionContext(projectID: draft.projectID, environmentID: nil)
                self.preview = try await self.executor.preview(draft: draft)
                let result = try await self.executor.execute(draft: draft, context: context)
                guard !Task.isCancelled else {
                    self.executionState = .cancelled
                    self.lastError = .cancelled
                    return
                }
                if case .rest(let artifact) = result {
                    self.response = artifact
                    self.lastError = artifact.error
                    await self.formatResponseBody(artifact)
                }
                self.executionState = .idle
            } catch let error as RESTExecutionError {
                if case .cancelled = error {
                    self.executionState = .cancelled
                    self.lastError = error
                } else {
                    self.executionState = .idle
                    self.lastError = error
                    self.response = self.errorArtifact(for: error)
                }
            } catch is CancellationError {
                self.executionState = .cancelled
                self.lastError = .cancelled
            } catch {
                self.executionState = .idle
                self.lastError = .transport(.unknown(error.localizedDescription))
                self.response = self.errorArtifact(for: .transport(.unknown(error.localizedDescription)))
            }
        }
    }

    func cancel() {
        cancelInFlightOnly()
        if executionState == .running {
            executionState = .cancelled
            lastError = .cancelled
            response = errorArtifact(for: .cancelled)
        }
    }

    func formatJSONBody() {
        jsonFormatToken = UUID()
    }

    private func cancelInFlightOnly() {
        sendTask?.cancel()
        sendTask = nil
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

    private func errorArtifact(for error: RESTExecutionError) -> RESTResponseArtifact {
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
