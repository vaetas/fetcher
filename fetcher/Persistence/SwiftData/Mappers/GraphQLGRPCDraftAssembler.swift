import Foundation

extension RequestDraftAssembler {
    static func makeAPIDraft(
        request: RequestRecord,
        project: ProjectRecord,
        environment: EnvironmentRecord?,
        secretValues: [UUID: String]
    ) throws -> APIRequestDraft {
        switch request.protocolKind {
        case .rest:
            return .rest(makeDraft(
                request: request,
                project: project,
                environment: environment,
                secretValues: secretValues
            ))
        case .graphql:
            return .graphql(makeGraphQLDraft(
                request: request,
                project: project,
                environment: environment,
                secretValues: secretValues
            ))
        case .grpc:
            return .grpc(try makeGRPCDraft(
                request: request,
                project: project,
                environment: environment,
                secretValues: secretValues
            ))
        }
    }

    static func makeGraphQLDraft(
        request: RequestRecord,
        project: ProjectRecord,
        environment: EnvironmentRecord?,
        secretValues: [UUID: String]
    ) -> GraphQLRequestDraft {
        let graphql = request.graphqlConfiguration
        let auth = request.auth
        let parameters = request.parameters.sorted { $0.sortIndex < $1.sortIndex }
        let headers = parameters.filter { $0.kind == .header }.map {
            KeyValueEntry(id: $0.id, key: $0.key, value: $0.value, isEnabled: $0.isEnabled)
        }
        let authPayload = AuthPayload.decode(from: auth?.nonSecretJSON ?? Data("{}".utf8))
        let (variables, secretVariables) = environmentVariables(environment, secretValues: secretValues)
        let baseURL = environment?.baseURL.isEmpty == false ? (environment?.baseURL ?? project.baseURL) : project.baseURL

        return GraphQLRequestDraft(
            requestID: request.id,
            projectID: project.id,
            name: request.name,
            definitionSourceID: (project.graphQLDefinitionSourceID ?? graphql?.definitionSourceID)
                .map(DefinitionSourceID.init(rawValue:)),
            endpoint: graphql?.endpoint ?? "",
            document: graphql?.document ?? "query {\n  \n}\n",
            operationName: graphql?.operationName,
            variablesJSON: graphql?.variablesJSON ?? "{}",
            extensionsJSON: graphql?.extensionsJSON,
            methodPreference: graphql?.methodPreference ?? .post,
            headers: headers,
            authKind: auth?.authKind ?? .none,
            bearerToken: auth?.secretReferenceIDs.first.flatMap { secretValues[$0] } ?? authPayload.bearerToken,
            bearerPrefix: authPayload.bearerPrefix ?? "Bearer",
            basicUsername: authPayload.basicUsername,
            basicPassword: auth?.secretReferenceIDs.first.flatMap { secretValues[$0] },
            apiKeyName: authPayload.apiKeyName,
            apiKeyValue: auth?.secretReferenceIDs.first.flatMap { secretValues[$0] },
            apiKeyLocation: authPayload.apiKeyLocation ?? .header,
            timeoutSeconds: graphql?.timeoutSeconds ?? project.defaultTimeoutSeconds,
            baseURL: baseURL,
            variables: variables,
            secretVariables: secretVariables
        )
    }

    static func makeGRPCDraft(
        request: RequestRecord,
        project: ProjectRecord,
        environment: EnvironmentRecord?,
        secretValues: [UUID: String]
    ) throws -> GRPCRequestDraft {
        guard let grpc = request.grpcConfiguration else {
            throw GRPCExecutionError.missingDefinition
        }
        guard let definitionID = grpc.definitionSourceID else {
            throw GRPCExecutionError.missingDefinition
        }
        let parameters = request.parameters.sorted { $0.sortIndex < $1.sortIndex }
        let metadata = parameters.filter { $0.kind == .header }.map {
            KeyValueEntry(id: $0.id, key: $0.key, value: $0.value, isEnabled: $0.isEnabled, isSecret: false)
        }
        let (variables, secretVariables) = environmentVariables(environment, secretValues: secretValues)
        let deadline = grpc.deadlineSeconds.map { DurationConfiguration(seconds: $0) }

        return GRPCRequestDraft(
            requestID: request.id,
            projectID: project.id,
            name: request.name,
            definitionSourceID: DefinitionSourceID(rawValue: definitionID),
            target: grpc.target,
            serviceFullName: grpc.serviceFullName,
            methodName: grpc.methodName,
            metadata: metadata,
            bodyJSON: grpc.bodyJSON,
            outboundMessagesJSON: grpc.outboundMessages,
            deadline: deadline,
            tls: grpc.tls,
            authorityOverride: grpc.authorityOverride,
            requestCompression: grpc.compressionRaw.flatMap(GRPCCompressionPreference.init(rawValue:)),
            variables: variables,
            secretVariables: secretVariables
        )
    }

    private static func environmentVariables(
        _ environment: EnvironmentRecord?,
        secretValues: [UUID: String]
    ) -> (variables: [String: String], secretVariables: [String: String]) {
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
        return (variables, secretVariables)
    }
}
