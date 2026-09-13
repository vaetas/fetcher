import SwiftUI

struct EditorDiagnosticsList: View {
    let diagnostics: [EditorDiagnostic]
    var onSelect: ((EditorDiagnostic) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            List(diagnostics) { diagnostic in
                Button {
                    onSelect?(diagnostic)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: iconName(for: diagnostic.severity))
                            .foregroundStyle(color(for: diagnostic.severity))
                            .font(.caption)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(diagnostic.message)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            if let source = diagnostic.source {
                                Text(source)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: diagnostic))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(maxHeight: 120)
    }

    private func iconName(for severity: EditorDiagnostic.Severity) -> String {
        switch severity {
        case .error: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .information: "info.circle.fill"
        }
    }

    private func color(for severity: EditorDiagnostic.Severity) -> Color {
        switch severity {
        case .error: .red
        case .warning: .orange
        case .information: .secondary
        }
    }

    private func accessibilityLabel(for diagnostic: EditorDiagnostic) -> String {
        let severityLabel: String
        switch diagnostic.severity {
        case .error: severityLabel = "Error"
        case .warning: severityLabel = "Warning"
        case .information: severityLabel = "Information"
        }
        return "\(severityLabel): \(diagnostic.message)"
    }
}
