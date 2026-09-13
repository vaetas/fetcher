import AppKit
import SwiftUI

struct IntelligentCodeEditor: View {
    @Binding var text: String
    var isEditable: Bool = true
    var syntaxMode: CodeEditorSyntaxMode = .plain
    var contentIsJSON = false
    var isContentFullyLoaded = true
    var searchQuery: String = ""
    var activeSearchMatchIndex: Int = 0
    var diagnostics: [EditorDiagnostic] = []
    var completionProvider: ((String, Int) -> [CompletionItem])?
    var onDebouncedChange: ((String) -> Void)?

    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IntelligentNativeCodeEditor(
                text: $text,
                isEditable: isEditable,
                syntaxMode: syntaxMode,
                contentIsJSON: contentIsJSON,
                isContentFullyLoaded: isContentFullyLoaded,
                searchQuery: searchQuery,
                activeSearchMatchIndex: activeSearchMatchIndex,
                completionProvider: completionProvider,
                onEditingChanged: scheduleDebouncedChange
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !diagnostics.isEmpty {
                EditorDiagnosticsList(diagnostics: diagnostics)
            }
        }
        .onDisappear {
            debounceTask?.cancel()
        }
    }

    private func scheduleDebouncedChange() {
        debounceTask?.cancel()
        guard onDebouncedChange != nil else { return }
        let snapshot = text
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onDebouncedChange?(snapshot)
            }
        }
    }
}

struct IntelligentNativeCodeEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    var syntaxMode: CodeEditorSyntaxMode = .plain
    var contentIsJSON = false
    var isContentFullyLoaded = true
    var searchQuery: String = ""
    var activeSearchMatchIndex: Int = 0
    var completionProvider: ((String, Int) -> [CompletionItem])?
    var onEditingChanged: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        configure(textView: textView, scrollView: scrollView)
        textView.delegate = context.coordinator
        context.coordinator.applyContent(to: textView, scrollView: scrollView)
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
        context.coordinator.applyContent(to: textView, scrollView: nsView)
    }

    private func configure(textView: NSTextView, scrollView: NSScrollView) {
        textView.isEditable = isEditable
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IntelligentNativeCodeEditor
        var lastDisplayState: NativeCodeEditor.DisplayState?
        var lastAppliedText: String?
        var cachedBaseText: String?
        var cachedBaseAttributedString: NSAttributedString?
        var lastScrolledSearchQuery: String?
        var lastScrolledActiveMatchIndex: Int?
        var renderTask: Task<Void, Never>?
        private var renderGeneration = 0
        private var completionController: CodeCompletionController?

        init(_ parent: IntelligentNativeCodeEditor) {
            self.parent = parent
        }

        func applyContent(to textView: NSTextView, scrollView: NSScrollView) {
            updateTextContainerWidth(textView: textView, scrollView: scrollView)

            let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let displayState = NativeCodeEditor.DisplayState(
                text: parent.text,
                searchQuery: parent.searchQuery,
                activeSearchMatchIndex: parent.activeSearchMatchIndex,
                syntaxMode: parent.syntaxMode,
                isEditable: parent.isEditable,
                contentIsJSON: parent.contentIsJSON,
                isContentFullyLoaded: parent.isContentFullyLoaded
            )

            if let lastText = lastAppliedText,
               parent.text.hasPrefix(lastText),
               parent.text.count > lastText.count,
               displayState.searchQuery == lastDisplayState?.searchQuery,
               displayState.activeSearchMatchIndex == lastDisplayState?.activeSearchMatchIndex,
               !displayState.needsRichPresentation {
                appendPlainTextDelta(to: textView, from: lastText, font: font)
                lastDisplayState = displayState
                return
            }

            guard displayState != lastDisplayState else { return }
            renderTask?.cancel()

            if displayState.needsRichPresentation {
                scheduleRichContent(textView: textView, displayState: displayState, font: font)
            } else {
                textView.isRichText = false
                textView.string = parent.text
                textView.font = font
                lastAppliedText = parent.text
                cachedBaseText = nil
                cachedBaseAttributedString = nil
            }

            lastDisplayState = displayState
        }

        private func updateTextContainerWidth(textView: NSTextView, scrollView: NSScrollView) {
            let width = scrollView.contentSize.width
            guard width > 0 else { return }
            textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        }

        private func appendPlainTextDelta(to textView: NSTextView, from lastText: String, font: NSFont) {
            let delta = String(parent.text[lastText.endIndex...])
            guard !delta.isEmpty else { return }
            textView.isRichText = false
            textView.textStorage?.append(
                NSAttributedString(string: delta, attributes: CodeEditorContentRenderer.plainAttributes(font: font))
            )
            lastAppliedText = parent.text
        }

        func scheduleRichContent(textView: NSTextView, displayState: NativeCodeEditor.DisplayState, font: NSFont) {
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
                applyAttributedContent(cachedBaseAttributedString, matches: [], textView: textView, displayState: displayState)
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
                    applyAttributedContent(result.0, matches: result.1, textView: textView, displayState: displayState)
                }
            }
        }

        private func applyAttributedContent(
            _ attributed: NSAttributedString,
            matches: [NSRange],
            textView: NSTextView,
            displayState: NativeCodeEditor.DisplayState
        ) {
            textView.isRichText = true
            textView.importsGraphics = false
            textView.textStorage?.setAttributedString(attributed)
            lastAppliedText = displayState.text
            scrollToActiveMatchIfNeeded(matches: matches, textView: textView, displayState: displayState)
            textView.needsDisplay = true
        }

        private func scrollToActiveMatchIfNeeded(
            matches: [NSRange],
            textView: NSTextView,
            displayState: NativeCodeEditor.DisplayState
        ) {
            guard !matches.isEmpty else { return }
            let clampedIndex = min(max(0, displayState.activeSearchMatchIndex), matches.count - 1)
            let searchChanged = lastScrolledSearchQuery != displayState.searchQuery
            let matchChanged = lastScrolledActiveMatchIndex != clampedIndex
            let textChanged = lastDisplayState?.text != displayState.text
            guard searchChanged || matchChanged || textChanged else { return }
            textView.scrollRangeToVisible(matches[clampedIndex])
            lastScrolledSearchQuery = displayState.searchQuery
            lastScrolledActiveMatchIndex = clampedIndex
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onEditingChanged?()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.complete(_:)) {
                showCompletions(in: textView)
                return true
            }
            return false
        }

        private func showCompletions(in textView: NSTextView) {
            guard let provider = parent.completionProvider else { return }
            let cursor = textView.selectedRange().location
            let items = provider(textView.string, cursor)
            guard !items.isEmpty else { return }
            completionController?.dismiss()
            let controller = CodeCompletionController(items: items) { [weak self] item in
                guard let self else { return }
                let selected = textView.selectedRange()
                textView.insertText(item.insertText, replacementRange: selected)
                parent.text = textView.string
                parent.onEditingChanged?()
                completionController?.dismiss()
                completionController = nil
            }
            completionController = controller
            controller.present(relativeTo: textView.selectedRange(), in: textView)
        }
    }
}

private final class CodeCompletionController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let items: [CompletionItem]
    private let onSelect: (CompletionItem) -> Void
    private let popover: NSPopover
    private let tableView: NSTableView
    private var eventMonitor: Any?
    private var selectedIndex = 0

    init(items: [CompletionItem], onSelect: @escaping (CompletionItem) -> Void) {
        self.items = items
        self.onSelect = onSelect
        self.popover = NSPopover()
        self.tableView = NSTableView()
        super.init()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("completion"))
        column.title = "Completion"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 22
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.doubleAction = #selector(acceptSelection)
        tableView.target = self

        let height = min(240, items.count * 24 + 8)
        popover.contentSize = NSSize(width: 340, height: height)
        popover.behavior = .semitransient
        let controller = NSViewController()
        controller.view = tableView
        popover.contentViewController = controller
    }

    func present(relativeTo range: NSRange, in textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let anchor = NSRect(x: rect.minX, y: rect.minY, width: max(rect.width, 1), height: rect.height)
        popover.show(relativeTo: anchor, of: textView, preferredEdge: .maxY)
        tableView.reloadData()
        selectRow(0)
        installMonitor()
    }

    func dismiss() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        popover.close()
    }

    private func installMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.keyCode {
            case 125:
                selectRow(min(selectedIndex + 1, items.count - 1))
                return nil
            case 126:
                selectRow(max(selectedIndex - 1, 0))
                return nil
            case 36:
                acceptSelection()
                return nil
            case 53:
                dismiss()
                return nil
            default:
                return event
            }
        }
    }

    private func selectRow(_ row: Int) {
        selectedIndex = row
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    @objc private func acceptSelection() {
        guard selectedIndex >= 0, selectedIndex < items.count else {
            dismiss()
            return
        }
        onSelect(items[selectedIndex])
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let cell = NSTableCellView()
        let title = item.detail.map { "\(item.label) — \($0)" } ?? item.label
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        cell.textField = label
        cell.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectedIndex = tableView.selectedRow
    }
}
