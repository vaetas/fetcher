import Foundation

actor GRPCStreamSession {
    private(set) var state: GRPCStreamState = .idle
    private(set) var outboundMessages: [GRPCMessageEvent] = []
    private(set) var inboundMessages: [GRPCMessageEvent] = []
    private var outboundSequence = 0
    private var inboundSequence = 0
    private var sendHandler: (@Sendable (Data) async throws -> Void)?
    private var halfCloseHandler: (@Sendable () async throws -> Void)?
    private var cancelHandler: (@Sendable () -> Void)?
    private var receiveTask: Task<Void, Never>?

    func configure(
        send: @escaping @Sendable (Data) async throws -> Void,
        halfClose: @escaping @Sendable () async throws -> Void,
        cancel: @escaping @Sendable () -> Void,
        receive: @escaping @Sendable () async throws -> AsyncThrowingStream<Data, Error>
    ) {
        sendHandler = send
        halfCloseHandler = halfClose
        cancelHandler = cancel
        state = .connecting

        receiveTask = Task {
            do {
                let stream = try await receive()
                state = .active
                for try await bytes in stream {
                    if Task.isCancelled { break }
                    inboundSequence += 1
                    let json = String(data: bytes, encoding: .utf8) ?? bytes.base64EncodedString()
                    inboundMessages.append(GRPCMessageEvent(
                        sequence: inboundSequence,
                        direction: .inbound,
                        json: json
                    ))
                }
                if state != .cancelled && state != .failed {
                    state = .completed
                }
            } catch is CancellationError {
                if state != .failed {
                    state = .cancelled
                }
            } catch {
                state = .failed
            }
        }
    }

    func send(messageJSON: String, encodedBytes: Data) async throws {
        guard state == .connecting || state == .active else {
            throw GRPCExecutionError.transport("Stream is not active.")
        }
        guard let sendHandler else {
            throw GRPCExecutionError.transport("Stream send handler is unavailable.")
        }
        outboundSequence += 1
        outboundMessages.append(GRPCMessageEvent(
            sequence: outboundSequence,
            direction: .outbound,
            json: messageJSON
        ))
        try await sendHandler(encodedBytes)
        if state == .connecting {
            state = .active
        }
    }

    func halfClose() async throws {
        guard state == .active || state == .connecting else { return }
        try await halfCloseHandler?()
        state = .clientHalfClosed
    }

    func cancel() {
        cancelHandler?()
        receiveTask?.cancel()
        receiveTask = nil
        state = .cancelled
    }

    func waitForCompletion() async {
        _ = await receiveTask?.value
    }

    var allMessages: [GRPCMessageEvent] {
        (outboundMessages + inboundMessages).sorted { $0.sequence < $1.sequence }
    }
}
