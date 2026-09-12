import SwiftData
import SwiftUI

struct AuthEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var request: RequestRecord
    let project: ProjectRecord
    let secretStore: any SecretStore

    @State private var bearerToken = ""
    @State private var bearerPrefix = "Bearer"
    @State private var basicUsername = ""
    @State private var basicPassword = ""
    @State private var apiKeyName = ""
    @State private var apiKeyValue = ""
    @State private var apiKeyLocation: APIKeyLocation = .header
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            Form {
                Section("Authentication") {
                Picker("Type", selection: authKindBinding) {
                    ForEach(AuthKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
            }

            switch ensureAuth().authKind {
            case .none:
                Text("No authentication will be applied.")
                    .foregroundStyle(.secondary)
            case .inherit:
                Text("Uses project default auth (\(project.defaultAuthKind.displayName)).")
                    .foregroundStyle(.secondary)
            case .bearer:
                Section("Bearer Token") {
                    SecureField("Token", text: $bearerToken)
                    TextField("Prefix", text: $bearerPrefix)
                    Button("Save Secret") { Task { await persistSecrets() } }
                }
            case .basic:
                Section("Basic Auth") {
                    TextField("Username", text: $basicUsername)
                    SecureField("Password", text: $basicPassword)
                    Button("Save Secret") { Task { await persistSecrets() } }
                }
            case .apiKey:
                Section("API Key") {
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
            }
            .formStyle(.grouped)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .task {
            guard !didLoad else { return }
            await loadSecrets()
            didLoad = true
        }
        .onChange(of: bearerPrefix) { _, _ in persistNonSecret() }
        .onChange(of: basicUsername) { _, _ in persistNonSecret() }
        .onChange(of: apiKeyName) { _, _ in persistNonSecret() }
        .onChange(of: apiKeyLocation) { _, _ in persistNonSecret() }
    }

    private var authKindBinding: Binding<AuthKind> {
        Binding(
            get: { ensureAuth().authKind },
            set: {
                ensureAuth().authKind = $0
                persistNonSecret()
            }
        )
    }

    private func ensureAuth() -> RequestAuthRecord {
        if let auth = request.auth { return auth }
        let auth = RequestAuthRecord(requestID: request.id)
        request.auth = auth
        modelContext.insert(auth)
        return auth
    }

    private func persistNonSecret() {
        let auth = ensureAuth()
        let payload = AuthPayload(
            bearerToken: nil,
            bearerPrefix: bearerPrefix,
            basicUsername: basicUsername,
            apiKeyName: apiKeyName,
            apiKeyLocation: apiKeyLocation
        )
        auth.nonSecretJSON = payload.encode()
        request.updatedAt = .now
        try? modelContext.save()
    }

    private func loadSecrets() async {
        let auth = ensureAuth()
        let payload = AuthPayload.decode(from: auth.nonSecretJSON)
        bearerPrefix = payload.bearerPrefix ?? "Bearer"
        basicUsername = payload.basicUsername ?? ""
        apiKeyName = payload.apiKeyName ?? ""
        apiKeyLocation = payload.apiKeyLocation ?? .header

        if let refID = auth.secretReferenceIDs.first {
            let reference = SecretReference(id: refID, label: request.name)
            if let data = try? await secretStore.read(reference),
               let value = String(data: data, encoding: .utf8) {
                switch auth.authKind {
                case .bearer: bearerToken = value
                case .basic: basicPassword = value
                case .apiKey: apiKeyValue = value
                default: break
                }
            }
        }
    }

    private func persistSecrets() async {
        let auth = ensureAuth()
        persistNonSecret()
        let secretString: String
        switch auth.authKind {
        case .bearer: secretString = bearerToken
        case .basic: secretString = basicPassword
        case .apiKey: secretString = apiKeyValue
        default: return
        }
        let reference: SecretReference
        if let existing = auth.secretReferenceIDs.first {
            reference = SecretReference(id: existing, label: "\(request.name) auth")
        } else {
            reference = SecretReference(label: "\(request.name) auth")
            auth.secretReferenceIDs = [reference.id]
        }
        guard let data = secretString.data(using: .utf8) else { return }
        try? await secretStore.write(data, reference: reference)
        request.updatedAt = .now
        try? modelContext.save()
    }
}
