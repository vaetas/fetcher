import SwiftUI

struct MethodBadge: View {
    let method: String

    private var tint: Color {
        switch method.uppercased() {
        case "GET", "HEAD", "OPTIONS": .blue
        case "POST": .green
        case "PUT", "PATCH": .orange
        case "DELETE": .red
        default: .secondary
        }
    }

    var body: some View {
        Text(method.uppercased())
            .font(.caption.weight(.semibold).monospaced())
            .foregroundStyle(tint)
            .accessibilityLabel("HTTP method \(method.uppercased())")
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct KeyValueEditor: View {
    @Binding var entries: [KeyValueEntry]
    var keyPlaceholder: String = "Key"
    var valuePlaceholder: String = "Value"
    var keySuggestions: [String] = []
    var showSecretToggle: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($entries) { $entry in
                HStack(spacing: 8) {
                    Toggle("", isOn: $entry.isEnabled)
                        .toggleStyle(.checkbox)
                        .labelsHidden()
                        .accessibilityLabel("Enabled")

                    if keySuggestions.isEmpty {
                        TextField(keyPlaceholder, text: $entry.key)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField(keyPlaceholder, text: $entry.key)
                            .textFieldStyle(.roundedBorder)
                            .help(keySuggestions.prefix(8).joined(separator: ", "))
                    }

                    if entry.isSecret {
                        SecureField(valuePlaceholder, text: $entry.value)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField(valuePlaceholder, text: $entry.value)
                            .textFieldStyle(.roundedBorder)
                    }

                    if showSecretToggle {
                        Toggle(isOn: $entry.isSecret) {
                            Image(systemName: entry.isSecret ? "eye.slash" : "eye")
                        }
                        .toggleStyle(.button)
                        .help(entry.isSecret ? "Secret value" : "Plain value")
                        .accessibilityLabel(entry.isSecret ? "Secret" : "Not secret")
                    }

                    Button {
                        entries.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete row")
                    .accessibilityLabel("Delete row")
                }
            }

            Button("Add") {
                entries.append(KeyValueEntry())
            }
        }
    }
}

enum CodeEditorSyntaxMode {
    case plain
    case jsonWhenValid
}

struct NativeCodeEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    var syntaxMode: CodeEditorSyntaxMode = .plain
    var contentIsJSON = false
    var isContentFullyLoaded = true
    var searchQuery: String = ""
    var activeSearchMatchIndex: Int = 0
    var onEditingChanged: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        applyContent(to: textView, scrollView: scrollView, coordinator: context.coordinator)
        return scrollView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width,
              let height = proposal.height,
              width.isFinite,
              height.isFinite,
              height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        textView.isEditable = isEditable
        applyContent(to: textView, scrollView: nsView, coordinator: context.coordinator)
    }

    private func configureScrolling(textView: NSTextView, scrollView: NSScrollView) {
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        updateTextContainerWidth(textView: textView, scrollView: scrollView)
    }

    private func updateTextContainerWidth(textView: NSTextView, scrollView: NSScrollView) {
        let width = scrollView.contentSize.width
        guard width > 0 else { return }
        textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
    }

    private func applyContent(to textView: NSTextView, scrollView: NSScrollView, coordinator: Coordinator) {
        configureScrolling(textView: textView, scrollView: scrollView)

        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let displayState = DisplayState(
            text: text,
            searchQuery: searchQuery,
            activeSearchMatchIndex: activeSearchMatchIndex,
            syntaxMode: syntaxMode,
            isEditable: isEditable,
            contentIsJSON: contentIsJSON,
            isContentFullyLoaded: isContentFullyLoaded
        )

        if let lastText = coordinator.lastAppliedText,
           text.hasPrefix(lastText),
           text.count > lastText.count,
           displayState.searchQuery == coordinator.lastDisplayState?.searchQuery,
           displayState.activeSearchMatchIndex == coordinator.lastDisplayState?.activeSearchMatchIndex,
           !displayState.needsRichPresentation {
            appendPlainTextDelta(
                to: textView,
                from: lastText,
                font: font,
                coordinator: coordinator
            )
            coordinator.lastDisplayState = displayState
            return
        }

        guard displayState != coordinator.lastDisplayState else { return }
        coordinator.renderTask?.cancel()

        if displayState.needsRichPresentation {
            coordinator.scheduleRichContent(
                textView: textView,
                displayState: displayState,
                font: font
            )
        } else {
            textView.isRichText = false
            textView.string = text
            textView.font = font
            coordinator.lastAppliedText = text
            coordinator.cachedBaseText = nil
            coordinator.cachedBaseAttributedString = nil
        }

        coordinator.lastDisplayState = displayState
    }

    private func appendPlainTextDelta(
        to textView: NSTextView,
        from lastText: String,
        font: NSFont,
        coordinator: Coordinator
    ) {
        let delta = String(text[lastText.endIndex...])
        guard !delta.isEmpty else { return }

        textView.isRichText = false
        textView.textStorage?.append(NSAttributedString(string: delta, attributes: CodeEditorContentRenderer.plainAttributes(font: font)))
        coordinator.lastAppliedText = text
    }

    private func scrollToActiveMatchIfNeeded(
        matches: [NSRange],
        textView: NSTextView,
        coordinator: Coordinator,
        displayState: DisplayState
    ) {
        guard !matches.isEmpty else { return }
        let clampedIndex = min(max(0, displayState.activeSearchMatchIndex), matches.count - 1)
        let searchChanged = coordinator.lastScrolledSearchQuery != displayState.searchQuery
        let matchChanged = coordinator.lastScrolledActiveMatchIndex != clampedIndex
        let textChanged = coordinator.lastDisplayState?.text != displayState.text
        guard searchChanged || matchChanged || textChanged else { return }

        textView.scrollRangeToVisible(matches[clampedIndex])
        coordinator.lastScrolledSearchQuery = displayState.searchQuery
        coordinator.lastScrolledActiveMatchIndex = clampedIndex
    }

    struct DisplayState: Equatable {
        var text: String
        var searchQuery: String
        var activeSearchMatchIndex: Int
        var syntaxMode: CodeEditorSyntaxMode
        var isEditable: Bool
        var contentIsJSON: Bool
        var isContentFullyLoaded: Bool

        var needsRichPresentation: Bool {
            let hasSearch = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let shouldHighlightJSON = CodeEditorContentRenderer.shouldSyntaxHighlight(
                text: text,
                isJSON: contentIsJSON,
                syntaxMode: syntaxMode,
                isEditable: isEditable
            )
            return isContentFullyLoaded && (shouldHighlightJSON || hasSearch)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeCodeEditor
        var lastDisplayState: DisplayState?
        var lastAppliedText: String?
        var cachedBaseText: String?
        var cachedBaseAttributedString: NSAttributedString?
        var lastScrolledSearchQuery: String?
        var lastScrolledActiveMatchIndex: Int?
        var renderTask: Task<Void, Never>?
        private var renderGeneration = 0

        init(_ parent: NativeCodeEditor) {
            self.parent = parent
        }

        func scheduleRichContent(textView: NSTextView, displayState: DisplayState, font: NSFont) {
            renderGeneration += 1
            let generation = renderGeneration
            let shouldHighlightJSON = CodeEditorContentRenderer.shouldSyntaxHighlight(
                text: displayState.text,
                isJSON: displayState.contentIsJSON,
                syntaxMode: displayState.syntaxMode,
                isEditable: displayState.isEditable
            )

            if let cachedBaseText,
               cachedBaseText == displayState.text,
               let cachedBaseAttributedString,
               displayState.searchQuery.isEmpty {
                applyAttributedContent(
                    cachedBaseAttributedString,
                    matches: [],
                    textView: textView,
                    displayState: displayState
                )
                return
            }

            let textCopy = displayState.text
            let searchCopy = displayState.searchQuery
            let activeIndex = displayState.activeSearchMatchIndex

            renderTask = Task {
                let result = await Task.detached(priority: .utility) {
                    CodeEditorContentRenderer.buildAttributedString(
                        text: textCopy,
                        font: font,
                        shouldHighlightJSON: shouldHighlightJSON,
                        searchQuery: searchCopy,
                        activeSearchMatchIndex: activeIndex
                    )
                }.value

                guard !Task.isCancelled, generation == renderGeneration else { return }

                await MainActor.run {
                    guard generation == renderGeneration else { return }
                    if searchCopy.isEmpty, shouldHighlightJSON {
                        cachedBaseText = textCopy
                        cachedBaseAttributedString = result.0
                    } else {
                        cachedBaseText = nil
                        cachedBaseAttributedString = nil
                    }
                    applyAttributedContent(
                        result.0,
                        matches: result.1,
                        textView: textView,
                        displayState: displayState
                    )
                }
            }
        }

        private func applyAttributedContent(
            _ attributed: NSAttributedString,
            matches: [NSRange],
            textView: NSTextView,
            displayState: DisplayState
        ) {
            textView.isRichText = true
            textView.importsGraphics = false
            textView.textStorage?.setAttributedString(attributed)
            lastAppliedText = displayState.text
            parent.scrollToActiveMatchIfNeeded(
                matches: matches,
                textView: textView,
                coordinator: self,
                displayState: displayState
            )
            textView.needsDisplay = true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onEditingChanged?()
        }
    }
}
