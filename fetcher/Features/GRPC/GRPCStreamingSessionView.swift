import SwiftUI

struct GRPCStreamingSessionView: View {
    let streamState: GRPCStreamState
    @Binding var outboundJSON: String
    let inboundMessages: [GRPCMessageEvent]
    var onSendMessage: () -> Void
    var onCompleteSending: () -> Void
    var onCancel: () -> Void

    @State private var selectedInboundID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controlsBar
            Divider()
            HSplitView {
                outboundPane
                    .frame(minWidth: 220, idealWidth: 320)
                inboundTimeline
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controlsBar: some View {
        HStack(spacing: 12) {
            Label(streamState.rawValue.capitalized, systemImage: streamIcon)
                .foregroundStyle(streamColor)

            Button("Send Message", action: onSendMessage)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [.command, .shift])

            Button("Complete Sending", action: onCompleteSending)
                .disabled(!canCompleteSending)

            Button("Cancel", role: .destructive, action: onCancel)
                .disabled(!canCancel)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var outboundPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Outbound message")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 8)
            NativeCodeEditor(
                text: $outboundJSON,
                syntaxMode: .jsonWhenValid,
                contentIsJSON: true
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private var inboundTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inbound timeline")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            if inboundMessages.isEmpty {
                EmptyStateView(title: "No Inbound Messages", message: "Messages received from the server will appear here.")
            } else {
                List(selection: $selectedInboundID) {
                    ForEach(inboundMessages.filter { $0.direction == .inbound }) { message in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("#\(message.sequence)")
                                    .font(.caption.monospaced())
                                Spacer()
                                Text(message.arrivedAt, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(messagePreview(message.json))
                                .font(.caption.monospaced())
                                .lineLimit(2)
                                .foregroundStyle(.secondary)
                        }
                        .tag(message.id)
                    }
                }
                .listStyle(.inset)
                if let selected = selectedInboundMessage {
                    NativeCodeEditor(
                        text: .constant(selected.json),
                        isEditable: false,
                        syntaxMode: .jsonWhenValid,
                        contentIsJSON: true
                    )
                    .padding(8)
                }
            }
        }
    }

    private var selectedInboundMessage: GRPCMessageEvent? {
        let inbound = inboundMessages.filter { $0.direction == .inbound }
        if let selectedInboundID {
            return inbound.first { $0.id == selectedInboundID }
        }
        return inbound.last
    }

    private var canSend: Bool {
        switch streamState {
        case .active, .connecting, .clientHalfClosed:
            return true
        case .idle, .completed, .cancelled, .failed:
            return false
        }
    }

    private var canCompleteSending: Bool {
        switch streamState {
        case .active, .clientHalfClosed:
            return true
        default:
            return false
        }
    }

    private var canCancel: Bool {
        switch streamState {
        case .connecting, .active, .clientHalfClosed:
            return true
        default:
            return false
        }
    }

    private var streamIcon: String {
        switch streamState {
        case .idle: "pause.circle"
        case .connecting: "arrow.triangle.2.circlepath"
        case .active: "bolt.circle"
        case .clientHalfClosed: "arrow.up.circle"
        case .completed: "checkmark.circle"
        case .cancelled: "xmark.circle"
        case .failed: "exclamationmark.circle"
        }
    }

    private var streamColor: Color {
        switch streamState {
        case .completed: .green
        case .failed, .cancelled: .red
        case .active, .connecting, .clientHalfClosed: .orange
        case .idle: .secondary
        }
    }

    private func messagePreview(_ json: String) -> String {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count > 120 {
            return String(singleLine.prefix(120)) + "…"
        }
        return singleLine
    }
}
