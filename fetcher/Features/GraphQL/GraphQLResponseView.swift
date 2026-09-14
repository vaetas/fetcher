import SwiftUI

enum GraphQLResponseSection: String, CaseIterable, Identifiable {
    case data
    case errors
    case extensions
    case headers
    case timing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .data: "Data"
        case .errors: "Errors"
        case .extensions: "Extensions"
        case .headers: "Headers"
        case .timing: "Timing"
        }
    }
}

struct GraphQLResponseView: View {
    let artifact: GraphQLResponseArtifact?
    let requestName: String
    @State private var selectedSection: GraphQLResponseSection = .data

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryBar
            Divider()

            if artifact == nil {
                EmptyStateView(
                    title: "No Response",
                    message: "Send the GraphQL request to inspect data, errors, extensions, headers, and timing."
                )
            } else {
                Picker("Response section", selection: $selectedSection) {
                    ForEach(availableSections) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(12)

                sectionContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: artifact?.id) { _, _ in
            selectedSection = defaultSection
        }
        .onAppear {
            selectedSection = defaultSection
        }
    }

    private var availableSections: [GraphQLResponseSection] {
        guard let artifact else { return GraphQLResponseSection.allCases }
        var sections: [GraphQLResponseSection] = []
        if artifact.dataJSON != nil { sections.append(.data) }
        if !artifact.errors.isEmpty || artifact.error != nil { sections.append(.errors) }
        if artifact.extensionsJSON != nil { sections.append(.extensions) }
        sections.append(.headers)
        sections.append(.timing)
        if sections.isEmpty { return [.data] }
        return sections
    }

    private var defaultSection: GraphQLResponseSection {
        guard let artifact else { return .data }
        if artifact.dataJSON != nil { return .data }
        if !artifact.errors.isEmpty || artifact.error != nil { return .errors }
        return .headers
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .data:
            jsonSection(text: artifact?.dataJSON, emptyTitle: "No Data", emptyMessage: "The response did not include a data field.")
        case .errors:
            errorsSection
        case .extensions:
            jsonSection(text: artifact?.extensionsJSON, emptyTitle: "No Extensions", emptyMessage: "The response did not include extensions.")
        case .headers:
            ResponseHeadersView(headers: artifact?.httpHeaders ?? [])
        case .timing:
            ResponseTimingView(metrics: artifact?.metrics)
        }
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
                if let status = artifact.httpStatusCode {
                    Text("\(status)")
                        .fontWeight(.semibold)
                        .foregroundStyle(statusColor(status))
                }
                if !artifact.errors.isEmpty {
                    Label("\(artifact.errors.count) GraphQL error(s)", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if artifact.dataJSON != nil {
                    Label("Data received", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if let duration = artifact.metrics?.totalDuration {
                    Text(formatDuration(duration))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Response")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let artifact, ResponseBodySaveSupport.isSaveable(artifact) {
                ResponseSaveAsButton(
                    requestName: requestName,
                    data: artifact.rawBody,
                    descriptor: ResponseBodySaveSupport.descriptor(for: artifact)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var errorsSection: some View {
        if let transportError = artifact?.error {
            VStack(alignment: .leading, spacing: 12) {
                Text(transportError.title).font(.headline)
                Text(transportError.message)
                NativeCodeEditor(text: .constant(String(describing: transportError)), isEditable: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 8)
            }
        } else if let errors = artifact?.errors, !errors.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(errors) { error in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(error.message)
                                .font(.headline)
                            if !error.path.isEmpty {
                                Text("Path: \(error.path.joined(separator: " → "))")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            if !error.locations.isEmpty {
                                Text(error.locations.map { "line \($0.line), column \($0.column)" }.joined(separator: "; "))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            if let extensionsJSON = error.extensionsJSON {
                                NativeCodeEditor(
                                    text: .constant(extensionsJSON),
                                    isEditable: false,
                                    syntaxMode: .jsonWhenValid,
                                    contentIsJSON: true
                                )
                                .frame(minHeight: 80)
                            }
                        }
                        Divider()
                    }
                }
                .padding()
            }
        } else {
            EmptyStateView(title: "No Errors", message: "The response did not report GraphQL errors.")
        }
    }

    @ViewBuilder
    private func jsonSection(text: String?, emptyTitle: String, emptyMessage: String) -> some View {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            NativeCodeEditor(
                text: .constant(text),
                isEditable: false,
                syntaxMode: .jsonWhenValid,
                contentIsJSON: true
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        } else {
            EmptyStateView(title: emptyTitle, message: emptyMessage)
        }
    }

    private func statusColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: .green
        case 400..<600: .red
        default: .secondary
        }
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        if value < 1 {
            return String(format: "%.0f ms", value * 1000)
        }
        return String(format: "%.2f s", value)
    }
}
