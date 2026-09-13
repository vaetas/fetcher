import SwiftUI

struct DefinitionInspector: View {
    let definition: APIDefinitionRecord
    var onRefresh: () -> Void

    var body: some View {
        ScrollView {
            Form {
                Section("Definition") {
                    LabeledContent("Name", value: definition.name)
                    LabeledContent("Protocol", value: definition.kind.displayName)
                    LabeledContent("Source kind", value: definition.sourceKindRawValue)
                }

                Section("Status") {
                    HStack {
                        DefinitionStatusIndicator(status: definition.status)
                        Text(definition.status.displayName)
                    }
                    if let fingerprint = definition.activeFingerprint {
                        LabeledContent("Fingerprint") {
                            Text(fingerprint)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .lineLimit(2)
                        }
                    }
                    if let refreshed = definition.lastSuccessfulRefreshAt {
                        LabeledContent("Last refresh") {
                            Text(refreshed, format: .dateTime)
                        }
                    } else {
                        LabeledContent("Last refresh", value: "Never")
                    }
                    if let attempted = definition.lastAttemptAt {
                        LabeledContent("Last attempt") {
                            Text(attempted, format: .dateTime)
                        }
                    }
                    if let error = definition.lastErrorMessage, !error.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last error")
                                .foregroundStyle(.secondary)
                            Text(error)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Button {
                        onRefresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(definition.status == .loading)
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
    }
}
