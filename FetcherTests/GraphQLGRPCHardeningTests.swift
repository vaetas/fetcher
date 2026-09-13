import Foundation
import SwiftData
import Testing
@testable import fetcher

struct SchemaResourceLimitsTests {
    @Test func limitsArePositiveAndBounded() {
        #expect(SchemaResourceLimits.maxFileCount > 0)
        #expect(SchemaResourceLimits.maxIndividualFileBytes > 0)
        #expect(SchemaResourceLimits.maxTotalSourceBytes >= SchemaResourceLimits.maxIndividualFileBytes)
        #expect(SchemaResourceLimits.maxRemoteRedirects >= 1)
        #expect(SchemaResourceLimits.maxStreamingMessagesRetained > 0)
        #expect(SchemaResourceLimits.maxSampleGenerationDepth >= 1)
    }
}

struct ContentFingerprintTests {
    @Test func fingerprintsAreStable() {
        let left = ContentFingerprint.sha256(of: "hello")
        let right = ContentFingerprint.sha256(of: "hello")
        #expect(left == right)
        #expect(left.count == 64)
        #expect(ContentFingerprint.sha256(of: "hello!") != left)
    }
}

struct APIRequestDraftTests {
    @Test func protocolKindMatchesCase() {
        let rest = APIRequestDraft.rest(sampleRESTDraft())
        #expect(rest.protocolKind == .rest)

        let graphql = APIRequestDraft.graphql(sampleGraphQLDraft())
        #expect(graphql.protocolKind == .graphql)

        let grpc = APIRequestDraft.grpc(sampleGRPCDraft())
        #expect(grpc.protocolKind == .grpc)
    }
}

struct GraphQLHTTPEncodingTests {
    @Test func responseParserSeparatesDataAndErrors() throws {
        let body = Data("""
        {
          "data": { "book": { "title": "Dune" } },
          "errors": [{ "message": "partial", "path": ["book", "author"] }],
          "extensions": { "traceId": "abc" }
        }
        """.utf8)
        let parsed = GraphQLResponseParser.parse(body: body)
        #expect(parsed.dataJSON?.contains("Dune") == true)
        #expect(parsed.errors.count == 1)
        #expect(parsed.errors[0].message == "partial")
        #expect(parsed.extensionsJSON?.contains("traceId") == true)
    }
}

struct SchemaSourceReaderLimitsTests {
    @Test func stagesOnlyProtoFilesAndSkipsGit() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temp)
            try? FileManager.default.removeItem(at: staging)
        }

        try FileManager.default.createDirectory(at: temp.appendingPathComponent(".git", isDirectory: true), withIntermediateDirectories: true)
        try Data("syntax = \"proto3\";".utf8).write(to: temp.appendingPathComponent("service.proto"))
        try Data("not a proto".utf8).write(to: temp.appendingPathComponent("readme.md"))
        try Data("ignored".utf8).write(to: temp.appendingPathComponent(".git/config"))

        let staged = try SchemaSourceReader().stageProtoSources(
            from: [temp],
            importRoots: [],
            into: staging
        )
        #expect(staged.rootFiles.count == 1)
        #expect(staged.rootFiles[0].lastPathComponent == "service.proto")
    }

    @Test func stagesMultipleContractFoldersAsImportRoots() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temp)
            try? FileManager.default.removeItem(at: staging)
        }

        let serviceDirectory = temp.appendingPathComponent("catalog-api/proto", isDirectory: true)
        let sharedDirectory = temp.appendingPathComponent("shared-contracts/proto", isDirectory: true)
        try FileManager.default.createDirectory(at: serviceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: sharedDirectory.appendingPathComponent("acme/orders/v1", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("syntax = \"proto3\"; import \"acme/orders/v1/types.proto\";".utf8)
            .write(to: serviceDirectory.appendingPathComponent("catalog.proto"))
        try Data("syntax = \"proto3\";".utf8)
            .write(to: sharedDirectory.appendingPathComponent("acme/orders/v1/types.proto"))

        let staged = try SchemaSourceReader().stageProtoSources(
            from: [serviceDirectory, sharedDirectory],
            importRoots: [],
            into: staging
        )

        #expect(staged.rootFiles.count == 2)
        #expect(staged.importRoots.count == 2)
        #expect(staged.importRoots.allSatisfy { $0.path.contains("/roots/directories/") })
        #expect(staged.rootFiles.contains { $0.path.hasSuffix("/acme/orders/v1/types.proto") })
    }

    @Test func stagesSelectedFilesFromTheSameFolderUnderOneImportRoot() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temp)
            try? FileManager.default.removeItem(at: staging)
        }

        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let request = temp.appendingPathComponent("request.proto")
        let types = temp.appendingPathComponent("types.proto")
        try Data("syntax = \"proto3\"; import \"types.proto\";".utf8).write(to: request)
        try Data("syntax = \"proto3\";".utf8).write(to: types)

        let staged = try SchemaSourceReader().stageProtoSources(
            from: [request, types],
            importRoots: [],
            into: staging
        )

        #expect(staged.rootFiles.count == 2)
        #expect(staged.importRoots.count == 1)
        #expect(staged.rootFiles.allSatisfy { $0.deletingLastPathComponent() == staged.importRoots[0] })
    }
}

struct ProtocDiscoveryTests {
    @Test func findsShellAndStandardMacOSCompilerLocations() {
        let candidates = ProtocSchemaCompiler.installedProtocCandidates(
            environment: [
                "PROTOC": "/custom-tools/protoc",
                "PATH": "/custom-bin:/usr/bin",
            ]
        )

        let paths = candidates.map(\.path)
        #expect(paths.first == "/custom-tools/protoc")
        #expect(paths.contains("/custom-bin/protoc"))
        #expect(paths.contains("/opt/homebrew/bin/protoc"))
        #expect(paths.contains("/usr/local/bin/protoc"))
    }

    @Test func trimsPROTOCOverride() {
        let candidates = ProtocSchemaCompiler.installedProtocCandidates(
            environment: ["PROTOC": "  /custom-tools/protoc  "]
        )

        #expect(candidates.first?.path == "/custom-tools/protoc")
    }

    @Test func prefersBundledHelperLocation() {
        let candidates = ProtocSchemaCompiler.bundledProtocCandidates()
        #expect(candidates.contains { $0.lastPathComponent == "protoc" })
        #expect(candidates.contains { $0.path.hasSuffix("Contents/Helpers/protoc") })
    }
}

struct MigrationCompatibilityTests {
    @Test func persistenceSchemaIncludesNewModels() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let project = ProjectRecord(name: "Compat")
        context.insert(project)

        let restRequest = RequestRecord(name: "REST", protocolKind: .rest, project: project)
        let rest = RESTRequestRecord(requestID: restRequest.id)
        restRequest.restConfiguration = rest
        context.insert(restRequest)
        context.insert(rest)

        let gqlRequest = RequestRecord(name: "GQL", protocolKind: .graphql, project: project)
        let gql = GraphQLRequestRecord(requestID: gqlRequest.id)
        gqlRequest.graphqlConfiguration = gql
        context.insert(gqlRequest)
        context.insert(gql)

        let grpcRequest = RequestRecord(name: "RPC", protocolKind: .grpc, project: project)
        let grpc = GRPCRequestRecord(requestID: grpcRequest.id)
        grpcRequest.grpcConfiguration = grpc
        context.insert(grpcRequest)
        context.insert(grpc)

        let definition = APIDefinitionRecord(
            projectID: project.id,
            name: "Books",
            kind: .graphql,
            sourceKindRawValue: GraphQLDefinitionSourceKind.endpointIntrospection.rawValue,
            configJSON: Data("{}".utf8),
            project: project
        )
        context.insert(definition)
        project.setSharedGraphQLDefinition(definition.id)
        try context.save()

        #expect(project.requests.count == 3)
        #expect(project.apiDefinitions.count == 1)
        #expect(project.graphQLDefinitionSourceID == definition.id)
        #expect(gql.definitionSourceID == definition.id)
        #expect(restRequest.protocolKind == .rest)
        #expect(gqlRequest.protocolKind == .graphql)
        #expect(grpcRequest.protocolKind == .grpc)
    }
}

struct GRPCStreamStateMachineTests {
    @Test func streamSessionHalfCloseAndCancel() async throws {
        let session = GRPCStreamSession()
        await session.configure(
            send: { _ in },
            halfClose: {},
            cancel: {},
            receive: {
                AsyncThrowingStream { continuation in
                    continuation.yield(Data("{}".utf8))
                    continuation.finish()
                }
            }
        )

        try await session.send(messageJSON: #"{"id":"1"}"#, encodedBytes: Data("{}".utf8))
        try await session.halfClose()
        let afterHalfClose = await session.state
        #expect(afterHalfClose == .clientHalfClosed || afterHalfClose == .completed || afterHalfClose == .active)

        await session.cancel()
        let afterCancel = await session.state
        #expect(afterCancel == .cancelled)

        let outbound = await session.outboundMessages
        #expect(outbound.count == 1)
    }
}

private func sampleRESTDraft() -> RESTRequestDraft {
    RESTRequestDraft(
        requestID: UUID(),
        projectID: UUID(),
        name: "REST",
        method: "GET",
        endpoint: "/",
        queryParameters: [],
        pathParameters: [],
        headers: [],
        bodyMode: .none,
        bodyText: "",
        authKind: .none,
        bearerToken: nil,
        bearerPrefix: "Bearer",
        basicUsername: nil,
        basicPassword: nil,
        apiKeyName: nil,
        apiKeyValue: nil,
        apiKeyLocation: .header,
        timeoutSeconds: 30,
        redirectPolicy: .follow,
        cookiePolicy: .isolatedEphemeral,
        cachePolicy: .ignoreLocalCache,
        tlsPolicy: .systemDefault,
        projectDefaultHeaders: [],
        projectAuthKind: .none,
        projectBearerToken: nil,
        projectBearerPrefix: "Bearer",
        projectBasicUsername: nil,
        projectBasicPassword: nil,
        projectAPIKeyName: nil,
        projectAPIKeyValue: nil,
        projectAPIKeyLocation: .header,
        baseURL: "http://localhost",
        variables: [:],
        secretVariables: [:]
    )
}

private func sampleGraphQLDraft() -> GraphQLRequestDraft {
    GraphQLRequestDraft(
        requestID: UUID(),
        projectID: UUID(),
        name: "GQL",
        definitionSourceID: nil,
        endpoint: "http://localhost/graphql",
        document: "query { __typename }",
        operationName: nil,
        variablesJSON: "{}",
        extensionsJSON: nil,
        methodPreference: .post,
        headers: [],
        authKind: .none,
        bearerToken: nil,
        bearerPrefix: "Bearer",
        basicUsername: nil,
        basicPassword: nil,
        apiKeyName: nil,
        apiKeyValue: nil,
        apiKeyLocation: .header,
        timeoutSeconds: 30,
        baseURL: "",
        variables: [:],
        secretVariables: [:]
    )
}

private func sampleGRPCDraft() -> GRPCRequestDraft {
    GRPCRequestDraft(
        requestID: UUID(),
        projectID: UUID(),
        name: "RPC",
        definitionSourceID: DefinitionSourceID(),
        target: "mock://local",
        serviceFullName: "test.Service",
        methodName: "Unary",
        metadata: [],
        bodyJSON: "{}",
        outboundMessagesJSON: [],
        deadline: DurationConfiguration(seconds: 30),
        tls: .plaintext,
        authorityOverride: nil,
        requestCompression: .none,
        variables: [:],
        secretVariables: [:]
    )
}
