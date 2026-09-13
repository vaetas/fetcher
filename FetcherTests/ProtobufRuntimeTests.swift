import Foundation
import Testing
@testable import fetcher

struct ProtobufRuntimeTests {
    let runtime = BuiltinDynamicProtobufRuntime()

    private func makeHelloRequestSnapshot() -> ProtobufSchemaSnapshot {
        let helloRequest = ProtoMessageDescriptor(
            fullName: "fetcher.test.HelloRequest",
            fields: [
                ProtoFieldDescriptor(
                    name: "name",
                    jsonName: "name",
                    number: 1,
                    typeName: "string",
                    cardinality: .optional,
                    oneofName: nil,
                    documentation: nil,
                    isDeprecated: false
                )
            ],
            nestedTypeNames: [],
            documentation: nil
        )

        let helloReply = ProtoMessageDescriptor(
            fullName: "fetcher.test.HelloReply",
            fields: [
                ProtoFieldDescriptor(
                    name: "message",
                    jsonName: "message",
                    number: 1,
                    typeName: "string",
                    cardinality: .optional,
                    oneofName: nil,
                    documentation: nil,
                    isDeprecated: false
                )
            ],
            nestedTypeNames: [],
            documentation: nil
        )

        let method = ProtoMethodDescriptor(
            serviceFullName: "fetcher.test.Greeter",
            name: "SayHello",
            inputType: ProtobufTypeID(fullName: "fetcher.test.HelloRequest"),
            outputType: ProtobufTypeID(fullName: "fetcher.test.HelloReply"),
            clientStreaming: false,
            serverStreaming: false,
            documentation: nil
        )

        let service = ProtoServiceDescriptor(
            fullName: "fetcher.test.Greeter",
            documentation: nil,
            methods: [method]
        )

        return ProtobufSchemaSnapshot(
            id: SchemaSnapshotID(),
            files: [ProtoFileDescriptor(name: "test.proto", package: "fetcher.test", dependencies: [])],
            servicesByName: ["fetcher.test.Greeter": service],
            messagesByName: [
                "fetcher.test.HelloRequest": helloRequest,
                "fetcher.test.HelloReply": helloReply
            ],
            enumsByName: [:],
            descriptorSetData: Data()
        )
    }

    @Test func jsonEncodeDecodeRoundtrip() throws {
        let snapshot = makeHelloRequestSnapshot()
        let registry = ProtobufRegistry(snapshot: snapshot)
        let messageType = ProtobufTypeID(fullName: "fetcher.test.HelloRequest")
        let json = #"{"name":"Fetcher"}"#

        let diagnostics = runtime.validateJSON(json, messageType: messageType, registry: registry)
        #expect(diagnostics.isEmpty)

        let encoded = try runtime.encodeProtoJSON(json, messageType: messageType, registry: registry)
        #expect(!encoded.isEmpty)

        let decoded = try runtime.decodeToProtoJSON(encoded, messageType: messageType, registry: registry)
        #expect(decoded.contains("Fetcher"))
    }

    @Test func rejectsUnknownJSONField() {
        let snapshot = makeHelloRequestSnapshot()
        let registry = ProtobufRegistry(snapshot: snapshot)
        let messageType = ProtobufTypeID(fullName: "fetcher.test.HelloRequest")
        let json = #"{"name":"Fetcher","unknownField":true}"#

        let diagnostics = runtime.validateJSON(json, messageType: messageType, registry: registry)
        #expect(diagnostics.contains { $0.message.contains("unknownField") })
    }

    @Test func indexesHandBuiltDescriptorSet() throws {
        let descriptorSet = try buildMinimalHelloDescriptorSet()
        let snapshot = try runtime.index(descriptorSet: descriptorSet)

        #expect(snapshot.servicesByName["fetcher.test.Greeter"] != nil)
        #expect(snapshot.method(serviceFullName: "fetcher.test.Greeter", methodName: "SayHello") != nil)
        #expect(snapshot.messagesByName["fetcher.test.HelloRequest"]?.fields.first?.jsonName == "name")
    }

    @Test func mockGRPCUnaryExecutorReturnsResponse() async throws {
        let snapshot = makeHelloRequestSnapshot()
        let registry = ProtobufRegistry(snapshot: snapshot)

        let invoker = GRPCDynamicInvoker(runtime: runtime, transport: MockGRPCTransport())
        let result = try await invoker.unary(
            target: "mock://local",
            serviceFullName: "fetcher.test.Greeter",
            methodName: "SayHello",
            requestJSON: #"{"name":"Fetcher"}"#,
            inputType: ProtobufTypeID(fullName: "fetcher.test.HelloRequest"),
            outputType: ProtobufTypeID(fullName: "fetcher.test.HelloReply"),
            registry: registry
        )

        #expect(result.status.code == 0)
        #expect(result.messageJSON == "{}")
    }

    @Test func grpcExecutorRequiresSchema() async {
        let executor = GRPCRequestExecutor(schemaProvider: EmptyGRPCSchemaProvider())
        let draft = GRPCRequestDraft(
            requestID: UUID(),
            projectID: UUID(),
            name: "Test",
            definitionSourceID: DefinitionSourceID(),
            target: "mock://local",
            serviceFullName: "fetcher.test.Greeter",
            methodName: "SayHello",
            metadata: [],
            bodyJSON: #"{"name":"Fetcher"}"#,
            outboundMessagesJSON: [],
            deadline: nil,
            tls: .plaintext,
            authorityOverride: nil,
            requestCompression: nil,
            variables: [:],
            secretVariables: [:]
        )

        do {
            _ = try await executor.execute(draft: draft, context: ExecutionContext(projectID: draft.projectID, environmentID: nil))
            Issue.record("Expected schema unavailable error.")
        } catch let failure as APIExecutionFailure {
            if case .grpc(.schemaUnavailable) = failure {
                #expect(Bool(true))
            } else {
                Issue.record("Unexpected failure: \(failure.message)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func buildMinimalHelloDescriptorSet() throws -> Data {
        var fileWriter = ProtobufWriter()

        var helloRequest = ProtobufWriter()
        helloRequest.writeString(fieldNumber: 1, "HelloRequest")
        var nameField = ProtobufWriter()
        nameField.writeString(fieldNumber: 1, "name")
        nameField.writeInt32(fieldNumber: 3, 1)
        nameField.writeInt32(fieldNumber: 4, 1)
        nameField.writeInt32(fieldNumber: 5, 9)
        helloRequest.writeEmbeddedMessage(fieldNumber: 2, nameField.data)

        var helloReply = ProtobufWriter()
        helloReply.writeString(fieldNumber: 1, "HelloReply")
        var messageField = ProtobufWriter()
        messageField.writeString(fieldNumber: 1, "message")
        messageField.writeInt32(fieldNumber: 3, 1)
        messageField.writeInt32(fieldNumber: 4, 1)
        messageField.writeInt32(fieldNumber: 5, 9)
        helloReply.writeEmbeddedMessage(fieldNumber: 2, messageField.data)

        var sayHello = ProtobufWriter()
        sayHello.writeString(fieldNumber: 1, "SayHello")
        sayHello.writeString(fieldNumber: 2, ".fetcher.test.HelloRequest")
        sayHello.writeString(fieldNumber: 3, ".fetcher.test.HelloReply")

        var greeter = ProtobufWriter()
        greeter.writeString(fieldNumber: 1, "Greeter")
        greeter.writeEmbeddedMessage(fieldNumber: 2, sayHello.data)

        var file = ProtobufWriter()
        file.writeString(fieldNumber: 1, "test.proto")
        file.writeString(fieldNumber: 2, "fetcher.test")
        file.writeEmbeddedMessage(fieldNumber: 4, helloRequest.data)
        file.writeEmbeddedMessage(fieldNumber: 4, helloReply.data)
        file.writeEmbeddedMessage(fieldNumber: 6, greeter.data)

        fileWriter.writeEmbeddedMessage(fieldNumber: 1, file.data)
        return fileWriter.data
    }
}
