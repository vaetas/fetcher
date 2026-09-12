import SwiftData
import SwiftUI

struct ProjectDefaultAuthEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var project: ProjectRecord
    let secretStore: any SecretStore

    @State private var bearerToken = ""
    @State private var bearerPrefix = "Bearer"
    @State private var basicUsername = ""
    @State private var basicPassword = ""
    @State private var apiKeyName = ""
    @State private var apiKeyValue = ""
    @State private var apiKeyLocation: APIKeyLocation = .header

    var body: some View {
        Section("Default Auth") {
            Picker("Type", selection: authKindBinding) {
                ForEach(AuthKind.allCases.filter { $0 != .inherit }, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }

            switch project.defaultAuthKind {
            case .none:
                Text("No default authentication will be applied to requests that inherit project auth.")
                    .foregroundStyle(.secondary)
            case .inherit:
                EmptyView()
            case .bearer:
                SecureField("Token", text: $bearerToken)
                TextField("Prefix", text: $bearerPrefix)
                Button("Save Secret") { Task { await persistSecrets() } }
            case .basic:
                TextField("Username", text: $basicUsername)
                SecureField("Password", text: $basicPassword)
                Button("Save Secret") { Task { await persistSecrets() } }
            case .apiKey:
                TextField("Key name", text: $apiKeyName)
                SecureField("Value", text: $apiKeyValue)
                Picker("Location", selection: $apiKeyLocation) {
                    ForEach(APIKeyLocation.allCases, id: \.self) { location in
                        Text(location.displayName).tag(location)
                    }
                }
                Button("Save Secret") { Task { await persistSecrets() } }
            }
        }
        .task(id: project.defaultAuthKind) {
            await loadSecrets()
        }
        .onChange(of: bearerPrefix) { _, _ in persistNonSecret() }
        .onChange(of: basicUsername) { _, _ in persistNonSecret() }
        .onChange(of: apiKeyName) { _, _ in persistNonSecret() }
        .onChange(of: apiKeyLocation) { _, _ in persistNonSecret() }
    }

    private var authKindBinding: Binding<AuthKind> {
        Binding(
            get: { project.defaultAuthKind },
            set: {
                project.defaultAuthKind = $0
                project.updatedAt = .now
                try? modelContext.save()
            }
        )
    }

    private func persistNonSecret() {
        let payload = AuthPayload(
            bearerToken: nil,
            bearerPrefix: bearerPrefix,
            basicUsername: basicUsername,
            apiKeyName: apiKeyName,
            apiKeyLocation: apiKeyLocation
        )
        project.defaultAuthNonSecretJSON = payload.encode()
        project.updatedAt = .now
        try? modelContext.save()
    }

    private func loadSecrets() async {
        let payload = AuthPayload.decode(from: project.defaultAuthNonSecretJSON)
        bearerPrefix = payload.bearerPrefix ?? "Bearer"
        basicUsername = payload.basicUsername ?? ""
        apiKeyName = payload.apiKeyName ?? ""
        apiKeyLocation = payload.apiKeyLocation ?? .header
        bearerToken = ""
        basicPassword = ""
        apiKeyValue = ""

        if let refID = project.defaultAuthSecretReferenceIDs.first {
            let reference = SecretReference(id: refID, label: project.name)
            if let data = try? await secretStore.read(reference),
               let value = String(data: data, encoding: .utf8) {
                switch project.defaultAuthKind {
                case .bearer: bearerToken = value
                case .basic: basicPassword = value
                case .apiKey: apiKeyValue = value
                default: break
                }
            }
        }
    }

    private func persistSecrets() async {
        persistNonSecret()
        let secretString: String
        switch project.defaultAuthKind {
        case .bearer: secretString = bearerToken
        case .basic: secretString = basicPassword
        case .apiKey: secretString = apiKeyValue
        default: return
        }
        let reference: SecretReference
        if let existing = project.defaultAuthSecretReferenceIDs.first {
            reference = SecretReference(id: existing, label: "\(project.name) default auth")
        } else {
            reference = SecretReference(label: "\(project.name) default auth")
            project.defaultAuthSecretReferenceIDs = [reference.id]
        }
        guard let data = secretString.data(using: .utf8) else { return }
        try? await secretStore.write(data, reference: reference)
        project.updatedAt = .now
        try? modelContext.save()
    }
}
