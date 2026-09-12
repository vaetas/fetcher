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
                .fixedSize(horizontal: false, vertical: true)
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

struct NativeCodeEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
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
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = text
        textView.autoresizingMask = [.width]
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .bezelBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if textView.string != text {
            textView.string = text
        }
        textView.isEditable = isEditable
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeCodeEditor

        init(_ parent: NativeCodeEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onEditingChanged?()
        }
    }
}
