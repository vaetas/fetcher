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
    var isFormattingResponse = false
    var jsonFormatToken = UUID()

    private let executor: RESTRequestExecutor
    private var sendTask: Task<Void, Never>?
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
            currentRequestID = requestID
        }
    }

    func send() {
        guard let draftBuilder else { return }
        cancelInFlightOnly()
        executionState = .running
        lastError = nil
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
        isFormattingResponse = true
        defer { isFormattingResponse = false }
        let data = artifact.body
        let mime = artifact.mimeType
        formattedResponseBody = await Task.detached(priority: .userInitiated) {
            ResponseBodyFormatter.format(data: data, mimeType: mime)
        }.value
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

enum ResponseBodyFormatter {
    static func format(data: Data, mimeType: String?) -> String {
        if data.isEmpty { return "" }

        if isBinary(data: data, mimeType: mimeType) {
            return "Binary response — \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
        }

        let looksJSON = mimeType?.contains("json") == true
            || ((try? JSONSerialization.jsonObject(with: data)) != nil)
        if looksJSON,
           let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        if let text = decodeText(data: data) {
            return text
        }
        return "Binary response — \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
    }

    static func decodeText(data: Data) -> String? {
        if data.contains(0) { return nil }
        if let utf8 = String(data: data, encoding: .utf8), utf8.utf8.count == data.count {
            return utf8
        }
        return nil
    }

    static func isBinary(data: Data, mimeType: String?) -> Bool {
        if mimeType?.hasPrefix("image/") == true { return true }
        if mimeType?.hasPrefix("audio/") == true { return true }
        if mimeType?.hasPrefix("video/") == true { return true }
        if mimeType == "application/octet-stream" { return true }
        if mimeType?.contains("json") == true { return false }
        if mimeType?.hasPrefix("text/") == true { return false }
        return decodeText(data: data) == nil
    }
}
