import SwiftUI

enum GRPCResponseDetailTab: String, CaseIterable, Identifiable {
    case metadata
    case trailers
    case details

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metadata: "Metadata"
        case .trailers: "Trailers"
        case .details: "Details"
        }
    }
}

struct GRPCResponseView: View {
    let artifact: GRPCResponseArtifact?
    let requestName: String
    @State private var selectedMessageID: UUID?
    @State private var detailTab: GRPCResponseDetailTab = .metadata

    var body: some View {
        if artifact == nil {
            EmptyStateView(
                title: "No Response",
                message: "Invoke the gRPC method to inspect messages, metadata, trailers, and status."
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                summaryBar
                Divider()
                HSplitView {
                    messagesList
                        .frame(minWidth: 180, idealWidth: 220)
                    VStack(alignment: .leading, spacing: 0) {
                        messageDetail
                        Divider()
                        detailTabs
                    }
                }
            }
        }
    }

    private var messages: [GRPCMessageEvent] {
        artifact?.messages ?? []
    }

    private var selectedMessage: GRPCMessageEvent? {
        if let selectedMessageID {
            return messages.first { $0.id == selectedMessageID }
        }
        return messages.last
    }

    private var summaryBar: some View {
        HStack(spacing: 16) {
            if let error = artifact?.error {
                Text(error.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
                Text(error.message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let artifact {
                Label(artifact.streamState.rawValue.capitalized, systemImage: streamIcon(for: artifact.streamState))
                    .foregroundStyle(streamColor(for: artifact.streamState))
                if let status = artifact.status {
                    Text("\(status.code) \(status.message)")
                        .fontWeight(.semibold)
                        .foregroundStyle(status.code == 0 ? .green : .red)
                }
                Text(artifact.callShape.displayName)
                    .foregroundStyle(.secondary)
                if let duration = artifact.metrics?.totalDuration {
                    Text(formatDuration(duration))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let artifact,
               let message = selectedMessage,
               ResponseBodySaveSupport.isSaveable(artifact, message: message) {
                ResponseSaveAsButton(
                    requestName: requestName,
                    data: Data(message.json.utf8),
                    descriptor: ResponseBodySaveSupport.descriptor(for: message)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var messagesList: some View {
        List(selection: $selectedMessageID) {
            if messages.isEmpty {
                Text("No messages yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(messages) { message in
                    HStack {
                        Image(systemName: message.direction == .inbound ? "arrow.down.circle" : "arrow.up.circle")
                            .foregroundStyle(message.direction == .inbound ? .blue : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("#\(message.sequence)")
                                .font(.caption.monospaced())
                            Text(message.direction.rawValue.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(message.id)
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear {
            selectedMessageID = messages.last?.id
        }
        .onChange(of: artifact?.messages.count) { _, _ in
            selectedMessageID = messages.last?.id
        }
    }

    @ViewBuilder
    private var messageDetail: some View {
        if let selectedMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(selectedMessage.direction.rawValue.capitalized) message #\(selectedMessage.sequence)")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                NativeCodeEditor(
                    text: .constant(selectedMessage.json),
                    isEditable: false,
                    syntaxMode: .jsonWhenValid,
                    contentIsJSON: true
                )
                .padding(.horizontal, 8)
            }
        } else {
            EmptyStateView(title: "No Message Selected", message: "Select a message to inspect its JSON payload.")
        }
    }

    private var detailTabs: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Detail", selection: $detailTab) {
                ForEach(GRPCResponseDetailTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Group {
                switch detailTab {
                case .metadata:
                    ResponseHeadersView(headers: artifact?.initialMetadata ?? [])
                case .trailers:
                    ResponseHeadersView(headers: artifact?.trailingMetadata ?? [])
                case .details:
                    detailsSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 160)
    }

    @ViewBuilder
    private var detailsSection: some View {
        ScrollView {
            Form {
                if let artifact {
                    LabeledContent("Target", value: artifact.target)
                    LabeledContent("Service", value: artifact.serviceFullName)
                    LabeledContent("Method", value: artifact.methodName)
                    LabeledContent("Call shape", value: artifact.callShape.displayName)
                    LabeledContent("Stream state", value: artifact.streamState.rawValue)
                    if let status = artifact.status {
                        LabeledContent("Status code", value: "\(status.code)")
                        LabeledContent("Status message", value: status.message)
                    }
                    if let detailsJSON = artifact.status?.detailsJSON {
                        Section("Status details") {
                            NativeCodeEditor(
                                text: .constant(detailsJSON),
                                isEditable: false,
                                syntaxMode: .jsonWhenValid,
                                contentIsJSON: true
                            )
                            .frame(minHeight: 80)
                        }
                    }
                    if let error = artifact.error {
                        Section("Error") {
                            Text(error.title).font(.headline)
                            Text(error.message)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func streamIcon(for state: GRPCStreamState) -> String {
        switch state {
        case .idle: "pause.circle"
        case .connecting: "arrow.triangle.2.circlepath"
        case .active: "bolt.circle"
        case .clientHalfClosed: "arrow.up.circle"
        case .completed: "checkmark.circle"
        case .cancelled: "xmark.circle"
        case .failed: "exclamationmark.circle"
        }
    }

    private func streamColor(for state: GRPCStreamState) -> Color {
        switch state {
        case .completed: .green
        case .failed, .cancelled: .red
        case .active, .connecting, .clientHalfClosed: .orange
        case .idle: .secondary
        }
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        if value < 1 {
            return String(format: "%.0f ms", value * 1000)
        }
        return String(format: "%.2f s", value)
    }
}
