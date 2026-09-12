import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ResponseContainerView: View {
    @Bindable var workspace: RequestWorkspaceModel
    @Binding var selectedTab: ResponseViewerTab

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryBar
            Divider()
            if workspace.response == nil && workspace.executionState != .running {
                EmptyStateView(
                    title: "No Response",
                    message: "Send the request to inspect status, headers, body, cookies, and timing here."
                )
            } else if workspace.executionState == .running {
                ProgressView("Waiting for response…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Picker("Response section", selection: $selectedTab) {
                    ForEach(ResponseViewerTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(12)

                Group {
                    switch selectedTab {
                    case .body:
                        ResponseBodyView(workspace: workspace)
                    case .headers:
                        ResponseHeadersView(headers: workspace.response?.headers ?? [])
                    case .cookies:
                        ResponseCookiesView(headers: workspace.response?.headers ?? [])
                    case .timing:
                        ResponseTimingView(metrics: workspace.response?.metrics)
                    case .raw:
                        RawResponseView(workspace: workspace)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summaryBar: some View {
        HStack(spacing: 16) {
            if let error = workspace.response?.error ?? workspace.lastError {
                Text(error.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(error == .cancelled ? Color.secondary : Color.red)
                Text(error.message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let response = workspace.response {
                Text(statusText(response.statusCode))
                    .fontWeight(.semibold)
                    .foregroundStyle(statusColor(response.statusCode))
                if let duration = response.metrics?.totalDuration ?? optionalDuration(response) {
                    Text(formatDuration(duration))
                        .foregroundStyle(.secondary)
                }
                Text(ByteCountFormatter.string(fromByteCount: Int64(response.body.count), countStyle: .file))
                    .foregroundStyle(.secondary)
                if let proto = response.metrics?.negotiatedProtocol {
                    Text(proto)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Response")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func statusText(_ code: Int?) -> String {
        guard let code else { return "—" }
        let message = HTTPURLResponse.localizedString(forStatusCode: code)
        return "\(code) \(message.capitalized)"
    }

    private func statusColor(_ code: Int?) -> Color {
        guard let code else { return .secondary }
        switch code {
        case 200..<300: return .green
        case 300..<400: return .orange
        default: return .red
        }
    }

    private func optionalDuration(_ response: RESTResponseArtifact) -> TimeInterval? {
        response.finishedAt.timeIntervalSince(response.startedAt)
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        if value < 1 {
            return String(format: "%.0f ms", value * 1000)
        }
        return String(format: "%.2f s", value)
    }
}

struct ResponseBodyView: View {
    @Bindable var workspace: RequestWorkspaceModel
    @State private var searchText = ""
    @State private var activeMatchIndex = 0
    @State private var searchMatchCount = 0

    private var bodyText: String {
        workspace.formattedResponseBody ?? ""
    }

    private var clampedActiveMatchIndex: Int {
        guard searchMatchCount > 0 else { return 0 }
        return min(activeMatchIndex, searchMatchCount - 1)
    }

    private var searchTaskKey: String {
        "\(searchText)|\(bodyText.count)|\(workspace.isResponseBodyFullyLoaded)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(bodyText, forType: .string)
                }
                .disabled(workspace.formattedResponseBody == nil)

                Button("Save As…") {
                    saveBody()
                }
                .disabled(workspace.response == nil)

                if workspace.isFormattingResponse {
                    ProgressView()
                        .controlSize(.small)
                }

                if let notice = workspace.responseBodyNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                ResponseBodySearchControls(
                    searchText: $searchText,
                    activeMatchIndex: $activeMatchIndex,
                    matchCount: searchMatchCount
                )
            }
            .padding(.horizontal)

            if let error = workspace.response?.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.title).font(.headline)
                    Text(error.message)
                    DisclosureGroup("Technical details") {
                        Text(String(describing: error))
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                }
                .padding()
            } else {
                NativeCodeEditor(
                    text: Binding(
                        get: { bodyText },
                        set: { _ in }
                    ),
                    isEditable: false,
                    syntaxMode: .jsonWhenValid,
                    contentIsJSON: workspace.responseBodyIsJSON,
                    isContentFullyLoaded: workspace.isResponseBodyFullyLoaded,
                    searchQuery: searchText,
                    activeSearchMatchIndex: clampedActiveMatchIndex
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 8)
        .onChange(of: searchText) { _, _ in
            activeMatchIndex = 0
        }
        .onChange(of: searchMatchCount) { _, count in
            if activeMatchIndex >= count {
                activeMatchIndex = max(0, count - 1)
            }
        }
        .onChange(of: workspace.formattedResponseBody) { _, _ in
            activeMatchIndex = 0
        }
        .task(id: searchTaskKey) {
            let query = searchText
            let text = bodyText
            let count = await Task.detached(priority: .utility) {
                EditorSearchHighlighter.ranges(of: query, in: text).count
            }.value
            guard !Task.isCancelled else { return }
            searchMatchCount = count
            if activeMatchIndex >= count {
                activeMatchIndex = max(0, count - 1)
            }
        }
    }

    private func saveBody() {
        guard let data = workspace.response?.body else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.data, .json, .plainText]
        panel.nameFieldStringValue = "response.bin"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }
}

private struct ResponseBodySearchControls: View {
    @Binding var searchText: String
    @Binding var activeMatchIndex: Int
    let matchCount: Int

    var body: some View {
        HStack(spacing: 6) {
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140, idealWidth: 180, maxWidth: 220)
                .accessibilityLabel("Search response body")

            if matchCount > 0 {
                Text("\(activeMatchIndex + 1)/\(matchCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("Match \(activeMatchIndex + 1) of \(matchCount)")
            }

            Button {
                moveToPreviousMatch()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(matchCount == 0)
            .help("Previous match")
            .accessibilityLabel("Previous match")

            Button {
                moveToNextMatch()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(matchCount == 0)
            .help("Next match")
            .accessibilityLabel("Next match")
        }
    }

    private func moveToNextMatch() {
        guard matchCount > 0 else { return }
        activeMatchIndex = (activeMatchIndex + 1) % matchCount
    }

    private func moveToPreviousMatch() {
        guard matchCount > 0 else { return }
        activeMatchIndex = (activeMatchIndex - 1 + matchCount) % matchCount
    }
}

struct ResponseHeadersView: View {
    let headers: [(String, String)]

    var body: some View {
        Table(headers.indices.map { IdentifiedHeader(id: $0, name: headers[$0].0, value: headers[$0].1) }) {
            TableColumn("Name") { row in
                Text(row.name)
                    .font(.body.monospaced())
                    .contextMenu {
                        Button("Copy Name") { copy(row.name) }
                        Button("Copy Value") { copy(row.value) }
                        Button("Copy Header") { copy("\(row.name): \(row.value)") }
                    }
            }
            TableColumn("Value") { row in
                Text(row.value)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}

private struct IdentifiedHeader: Identifiable {
    let id: Int
    let name: String
    let value: String
}

struct ResponseCookiesView: View {
    let headers: [(String, String)]

    private var cookies: [ParsedCookie] {
        headers
            .filter { $0.0.caseInsensitiveCompare("Set-Cookie") == .orderedSame }
            .enumerated()
            .map { ParsedCookie.parse(id: $0.offset, header: $0.element.1) }
    }

    var body: some View {
        if cookies.isEmpty {
            EmptyStateView(title: "No Cookies", message: "This response did not include Set-Cookie headers.")
        } else {
            Table(cookies) {
                TableColumn("Name", value: \.name)
                TableColumn("Value", value: \.value)
                TableColumn("Domain", value: \.domain)
                TableColumn("Path", value: \.path)
                TableColumn("Expires", value: \.expires)
                TableColumn("Secure") { cookie in Text(cookie.secure ? "✓" : "") }
                TableColumn("HttpOnly") { cookie in Text(cookie.httpOnly ? "✓" : "") }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
        }
    }
}

struct ParsedCookie: Identifiable {
    let id: Int
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: String
    var secure: Bool
    var httpOnly: Bool

    static func parse(id: Int, header: String) -> ParsedCookie {
        let parts = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        let nameValue = parts.first?.split(separator: "=", maxSplits: 1).map(String.init) ?? []
        var cookie = ParsedCookie(
            id: id,
            name: nameValue.first ?? "",
            value: nameValue.count > 1 ? nameValue[1] : "",
            domain: "",
            path: "",
            expires: "",
            secure: false,
            httpOnly: false
        )
        for part in parts.dropFirst() {
            let lower = part.lowercased()
            if lower == "secure" { cookie.secure = true }
            else if lower == "httponly" { cookie.httpOnly = true }
            else if lower.hasPrefix("domain=") { cookie.domain = String(part.dropFirst(7)) }
            else if lower.hasPrefix("path=") { cookie.path = String(part.dropFirst(5)) }
            else if lower.hasPrefix("expires=") { cookie.expires = String(part.dropFirst(8)) }
            else if lower.hasPrefix("max-age=") { cookie.expires = String(part.dropFirst(8)) }
        }
        return cookie
    }
}

struct ResponseTimingView: View {
    let metrics: RequestMetrics?

    var body: some View {
        ScrollView {
            Form {
                if let metrics {
                timingRow("DNS", metrics.dnsLookup)
                timingRow("Connect", metrics.tcpConnect)
                timingRow("TLS", metrics.tlsHandshake)
                timingRow("Request", metrics.requestDuration)
                timingRow("TTFB", metrics.timeToFirstByte)
                timingRow("Download", metrics.responseDownload)
                timingRow("Total", metrics.totalDuration)
                LabeledContent("Protocol", value: metrics.negotiatedProtocol ?? "—")
                LabeledContent("Reused connection", value: metrics.reusedConnection.map { $0 ? "Yes" : "No" } ?? "—")
                LabeledContent("Redirects", value: "\(metrics.redirectCount)")
            } else {
                Text("Timing metrics are unavailable for this response.")
                    .foregroundStyle(.secondary)
            }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }

    @ViewBuilder
    private func timingRow(_ title: String, _ value: TimeInterval?) -> some View {
        LabeledContent(title, value: value.map(format) ?? "—")
    }

    private func format(_ value: TimeInterval) -> String {
        String(format: "%.0f ms", value * 1000)
    }
}

struct RawResponseView: View {
    @Bindable var workspace: RequestWorkspaceModel

    var body: some View {
        let text = rawText
        NativeCodeEditor(
            text: .constant(text),
            isEditable: false
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }

    private var rawText: String {
        var lines: [String] = []
        if let preview = workspace.preview {
            lines.append("=== Resolved Request ===")
            lines.append(preview.resolvedURL)
            for (name, value) in preview.headers {
                lines.append("\(name): \(value)")
            }
            if let body = preview.bodyPreview {
                lines.append("")
                lines.append(body)
            }
            lines.append("")
        }
        lines.append("=== Response ===")
        if let response = workspace.response {
            if let error = response.error {
                lines.append("\(error.title): \(error.message)")
            } else {
                lines.append("\(response.statusCode.map(String.init) ?? "—") \(response.finalURL?.absoluteString ?? "")")
                for (name, value) in SecretRedactor.redactHeaders(response.headers) {
                    lines.append("\(name): \(value)")
                }
                lines.append("")
                lines.append(workspace.formattedResponseBody ?? ResponseBodyFormatter.format(data: response.body, mimeType: response.mimeType))
            }
        }
        return lines.joined(separator: "\n")
    }
}
