import SwiftUI

struct GRPCMethodPicker: View {
    let snapshot: ProtobufSchemaSnapshot
    @Binding var selectedService: String
    @Binding var selectedMethod: String
    @State private var searchText = ""

    private var filteredMethods: [ProtoMethodDescriptor] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let methods = snapshot.allMethods
        guard !query.isEmpty else { return methods }
        return methods.filter {
            $0.fullMethodName.localizedCaseInsensitiveContains(query)
                || $0.name.localizedCaseInsensitiveContains(query)
                || $0.serviceFullName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List(selection: methodSelectionBinding) {
            ForEach(groupedMethods.keys.sorted(), id: \.self) { service in
                Section(service) {
                    ForEach(groupedMethods[service] ?? [], id: \.fullMethodName) { method in
                        methodRow(method)
                            .tag(method.fullMethodName)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search services and methods")
    }

    private var groupedMethods: [String: [ProtoMethodDescriptor]] {
        Dictionary(grouping: filteredMethods, by: \.serviceFullName)
    }

    private var methodSelectionBinding: Binding<String?> {
        Binding(
            get: {
                guard !selectedService.isEmpty, !selectedMethod.isEmpty else { return nil }
                return "\(selectedService)/\(selectedMethod)"
            },
            set: { newValue in
                guard let newValue else {
                    selectedService = ""
                    selectedMethod = ""
                    return
                }
                let parts = newValue.split(separator: "/", maxSplits: 1).map(String.init)
                selectedService = parts.first ?? ""
                selectedMethod = parts.count > 1 ? parts[1] : ""
            }
        )
    }

    private func methodRow(_ method: ProtoMethodDescriptor) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(method.name)
                    .font(.body.monospaced())
                if let documentation = method.documentation, !documentation.isEmpty {
                    Text(documentation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(method.callShape.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("\(method.name), \(method.callShape.displayName)")
    }
}
