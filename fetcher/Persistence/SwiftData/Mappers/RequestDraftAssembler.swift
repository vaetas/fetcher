import Foundation
import SwiftData

enum RequestDraftAssembler {
    static func makeDraft(
        request: RequestRecord,
        project: ProjectRecord,
        environment: EnvironmentRecord?,
        secretValues: [UUID: String]
    ) -> RESTRequestDraft {
        let rest = request.restConfiguration
        let auth = request.auth
        let parameters = request.parameters.sorted { $0.sortIndex < $1.sortIndex }

        let query = parameters.filter { $0.kind == .query }.map {
            KeyValueEntry(id: $0.id, key: $0.key, value: $0.value, isEnabled: $0.isEnabled)
        }
        let path = parameters.filter { $0.kind == .path }.map {
            KeyValueEntry(id: $0.id, key: $0.key, value: $0.value, isEnabled: $0.isEnabled)
        }
        let headers = parameters.filter { $0.kind == .header }.map {
            KeyValueEntry(id: $0.id, key: $0.key, value: $0.value, isEnabled: $0.isEnabled)
        }

        let authPayload = AuthPayload.decode(from: auth?.nonSecretJSON ?? Data("{}".utf8))
        let projectAuthPayload = AuthPayload.decode(from: project.defaultAuthNonSecretJSON)
        let projectHeaders = (try? JSONDecoder().decode([KeyValueEntry].self, from: project.defaultHeadersJSON)) ?? []

        var variables: [String: String] = [:]
        var secretVariables: [String: String] = [:]
        if let environment {
            for variable in environment.variables where variable.isEnabled {
                if variable.isSecret, let ref = variable.secretReferenceID, let secret = secretValues[ref] {
                    secretVariables[variable.key] = secret
                } else if let value = variable.value {
                    variables[variable.key] = value
                }
            }
        }

        let bearerRef = auth?.secretReferenceIDs.first
        let basicPasswordRef = auth?.secretReferenceIDs.first
        let apiKeyRef = auth?.secretReferenceIDs.first

        return RESTRequestDraft(
            requestID: request.id,
            projectID: project.id,
            name: request.name,
            method: rest?.method ?? "GET",
            endpoint: rest?.endpoint ?? "/",
            queryParameters: query,
            pathParameters: path,
            headers: headers,
            bodyMode: rest?.bodyMode ?? .none,
            bodyText: rest?.bodyText ?? "",
            authKind: auth?.authKind ?? .none,
            bearerToken: bearerRef.flatMap { secretValues[$0] } ?? authPayload.bearerToken,
            bearerPrefix: authPayload.bearerPrefix ?? "Bearer",
            basicUsername: authPayload.basicUsername,
            basicPassword: basicPasswordRef.flatMap { secretValues[$0] },
            apiKeyName: authPayload.apiKeyName,
            apiKeyValue: apiKeyRef.flatMap { secretValues[$0] },
            apiKeyLocation: authPayload.apiKeyLocation ?? .header,
            timeoutSeconds: rest?.timeoutSeconds ?? project.defaultTimeoutSeconds,
            redirectPolicy: rest?.redirectPolicy ?? project.defaultRedirectPolicy,
            cookiePolicy: .isolatedEphemeral,
            cachePolicy: .ignoreLocalCache,
            tlsPolicy: .systemDefault,
            projectDefaultHeaders: projectHeaders,
            projectAuthKind: project.defaultAuthKind,
            projectBearerToken: project.defaultAuthSecretReferenceIDs.first.flatMap { secretValues[$0] } ?? projectAuthPayload.bearerToken,
            projectBearerPrefix: projectAuthPayload.bearerPrefix ?? "Bearer",
            projectBasicUsername: projectAuthPayload.basicUsername,
            projectBasicPassword: project.defaultAuthSecretReferenceIDs.first.flatMap { secretValues[$0] },
            projectAPIKeyName: projectAuthPayload.apiKeyName,
            projectAPIKeyValue: project.defaultAuthSecretReferenceIDs.first.flatMap { secretValues[$0] },
            projectAPIKeyLocation: projectAuthPayload.apiKeyLocation ?? .header,
            baseURL: environment?.baseURL.isEmpty == false ? (environment?.baseURL ?? project.baseURL) : project.baseURL,
            variables: variables,
            secretVariables: secretVariables
        )
    }
}

struct AuthPayload: Codable, Sendable {
    var bearerToken: String?
    var bearerPrefix: String?
    var basicUsername: String?
    var apiKeyName: String?
    var apiKeyLocation: APIKeyLocation?

    static func decode(from data: Data) -> AuthPayload {
        (try? JSONDecoder().decode(AuthPayload.self, from: data)) ?? AuthPayload()
    }

    func encode() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data("{}".utf8)
    }
}
