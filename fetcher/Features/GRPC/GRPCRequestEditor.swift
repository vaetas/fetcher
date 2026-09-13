import SwiftData
import SwiftUI

struct GRPCRequestEditor: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var request: RequestRecord
    let definitions: [APIDefinitionRecord]
    let schemaSnapshot: ProtobufSchemaSnapshot?
    var onInsertExampleBody: (() -> Void)?

    private var protobufDefinitions: [APIDefinitionRecord] {
        definitions.filter { $0.kind == .protobuf }
    }

    private var selectedMethod: ProtoMethodDescriptor? {
        guard let schemaSnapshot, let grpc = request.grpcConfiguration else { return nil }
        return schemaSnapshot.method(serviceFullName: grpc.serviceFullName, methodName: grpc.methodName)
    }

    private var callShape: GRPCCallShape {
        selectedMethod?.callShape ?? .unary
    }

    var body: some View {
        ScrollView {
            Form {
                Section("Target") {
                    TextField("Host:port", text: targetBinding)
                        .textFieldStyle(.roundedBorder)
                    Toggle("Use TLS", isOn: useTLSBinding)
                    if request.grpcConfiguration?.useTLS == true {
                        TextField("Authority override", text: authorityOverrideBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Section("Definition") {
                    if protobufDefinitions.isEmpty {
                        Text("Add a protobuf API definition to select services and methods.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Definition", selection: definitionSourceBinding) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(protobufDefinitions, id: \.id) { definition in
                                Text(definition.name).tag(Optional(definition.id))
                            }
                        }
                    }
                }

                if schemaSnapshot != nil {
                    Section("Method") {
                        Picker("Service", selection: serviceBinding) {
                            Text("Select service").tag("")
                            ForEach(sortedServices, id: \.fullName) { service in
                                Text(service.fullName).tag(service.fullName)
                            }
                        }
                        Picker("Method", selection: methodBinding) {
                            Text("Select method").tag("")
                            ForEach(methodsForSelectedService, id: \.name) { method in
                                Text(method.name).tag(method.name)
                            }
                        }
                        LabeledContent("Call shape", value: callShape.displayName)
                    }
                }

                Section("Body") {
                    if callShape == .unary || callShape == .serverStreaming {
                        HStack {
                            Button("Insert Example Body", action: { onInsertExampleBody?() })
                            Spacer()
                        }
                        NativeCodeEditor(
                            text: bodyJSONBinding,
                            syntaxMode: .jsonWhenValid,
                            contentIsJSON: true
                        )
                        .frame(minHeight: 160)
                    } else {
                        outboundMessagesEditor
                    }
                }

                Section("Metadata") {
                    KeyValueEditor(
                        entries: metadataBinding,
                        keyPlaceholder: "Metadata key",
                        valuePlaceholder: "Value"
                    )
                }
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
    }

    private var sortedServices: [ProtoServiceDescriptor] {
        guard let schemaSnapshot else { return [] }
        return schemaSnapshot.servicesByName.values.sorted {
            $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending
        }
    }

    private var methodsForSelectedService: [ProtoMethodDescriptor] {
        guard let schemaSnapshot, let serviceName = request.grpcConfiguration?.serviceFullName else { return [] }
        return schemaSnapshot.servicesByName[serviceName]?.methods.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        } ?? []
    }

    private var outboundMessagesEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(outboundMessagesBinding.wrappedValue.enumerated()), id: \.offset) { index, _ in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Message \(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            removeOutboundMessage(at: index)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete message \(index + 1)")
                    }
                    NativeCodeEditor(
                        text: outboundMessageBinding(at: index),
                        syntaxMode: .jsonWhenValid,
                        contentIsJSON: true
                    )
                    .frame(minHeight: 100)
                }
            }
            Button("Add Message") {
                addOutboundMessage()
            }
        }
    }

    private var targetBinding: Binding<String> {
        Binding(
            get: { ensureGRPC().target },
            set: {
                ensureGRPC().target = $0
                save()
            }
        )
    }

    private var useTLSBinding: Binding<Bool> {
        Binding(
            get: { ensureGRPC().useTLS },
            set: {
                ensureGRPC().useTLS = $0
                save()
            }
        )
    }

    private var authorityOverrideBinding: Binding<String> {
        Binding(
            get: { ensureGRPC().authorityOverride ?? "" },
            set: {
                ensureGRPC().authorityOverride = $0.isEmpty ? nil : $0
                save()
            }
        )
    }

    private var definitionSourceBinding: Binding<UUID?> {
        Binding(
            get: { ensureGRPC().definitionSourceID },
            set: {
                ensureGRPC().definitionSourceID = $0
                save()
            }
        )
    }

    private var serviceBinding: Binding<String> {
        Binding(
            get: { ensureGRPC().serviceFullName },
            set: {
                ensureGRPC().serviceFullName = $0
                ensureGRPC().methodName = ""
                save()
            }
        )
    }

    private var methodBinding: Binding<String> {
        Binding(
            get: { ensureGRPC().methodName },
            set: {
                ensureGRPC().methodName = $0
                save()
            }
        )
    }

    private var bodyJSONBinding: Binding<String> {
        Binding(
            get: { ensureGRPC().bodyJSON },
            set: {
                ensureGRPC().bodyJSON = $0
                save()
            }
        )
    }

    private var outboundMessagesBinding: Binding<[String]> {
        Binding(
            get: { ensureGRPC().outboundMessages },
            set: {
                ensureGRPC().outboundMessages = $0
                save()
            }
        )
    }

    private var metadataBinding: Binding<[KeyValueEntry]> {
        Binding(
            get: {
                request.parameters
                    .filter { $0.kind == .header }
                    .sorted { $0.sortIndex < $1.sortIndex }
                    .map { KeyValueEntry(id: $0.id, key: $0.key, value: $0.value, isEnabled: $0.isEnabled) }
            },
            set: { newEntries in
                let existing = request.parameters.filter { $0.kind == .header }
                for item in existing {
                    modelContext.delete(item)
                }
                for (index, entry) in newEntries.enumerated() {
                    let record = RequestParameterRecord(
                        id: entry.id,
                        kind: .header,
                        key: entry.key,
                        value: entry.value,
                        isEnabled: entry.isEnabled,
                        sortIndex: Double(index),
                        request: request
                    )
                    modelContext.insert(record)
                }
                save()
            }
        )
    }

    private func outboundMessageBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                let messages = ensureGRPC().outboundMessages
                guard index < messages.count else { return "{}" }
                return messages[index]
            },
            set: { newValue in
                var messages = ensureGRPC().outboundMessages
                guard index < messages.count else { return }
                messages[index] = newValue
                ensureGRPC().outboundMessages = messages
                save()
            }
        )
    }

    private func addOutboundMessage() {
        var messages = ensureGRPC().outboundMessages
        messages.append("{}")
        ensureGRPC().outboundMessages = messages
        save()
    }

    private func removeOutboundMessage(at index: Int) {
        var messages = ensureGRPC().outboundMessages
        guard index < messages.count else { return }
        messages.remove(at: index)
        ensureGRPC().outboundMessages = messages
        save()
    }

    private func ensureGRPC() -> GRPCRequestRecord {
        if let config = request.grpcConfiguration { return config }
        let config = GRPCRequestRecord(requestID: request.id)
        request.grpcConfiguration = config
        modelContext.insert(config)
        return config
    }

    private func save() {
        request.updatedAt = .now
        try? modelContext.save()
    }
}
