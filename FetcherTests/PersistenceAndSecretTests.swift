import Foundation
import SwiftData
import Testing
@testable import fetcher

struct PersistenceTests {
    @Test @MainActor
    func createProjectAndRequestCascade() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let project = ProjectRecord(name: "Worker API")
        let environment = EnvironmentRecord(name: "Development", baseURL: "http://localhost:8787", project: project)
        project.selectedEnvironmentID = environment.id
        let request = RequestRecord(name: "List books", project: project)
        let rest = RESTRequestRecord(requestID: request.id, method: "GET", endpoint: "/api/books")
        request.restConfiguration = rest

        context.insert(project)
        context.insert(environment)
        context.insert(request)
        context.insert(rest)
        try context.save()

        let projects = try context.fetch(FetchDescriptor<ProjectRecord>())
        #expect(projects.count == 1)
        #expect(projects[0].requests.count == 1)
        #expect(projects[0].requests[0].restConfiguration?.endpoint == "/api/books")

        context.delete(projects[0])
        try context.save()
        let remainingRequests = try context.fetch(FetchDescriptor<RequestRecord>())
        #expect(remainingRequests.isEmpty)
    }
}

actor InMemorySecretStore: SecretStore {
    private var storage: [UUID: Data] = [:]

    func read(_ reference: SecretReference) async throws -> Data? {
        storage[reference.id]
    }

    func write(_ data: Data, reference: SecretReference) async throws {
        storage[reference.id] = data
    }

    func delete(_ reference: SecretReference) async throws {
        storage.removeValue(forKey: reference.id)
    }
}

struct KeychainStoreTests {
    @Test func roundTripSecret() async throws {
        let store = InMemorySecretStore()
        let reference = SecretReference(label: "token")
        try await store.write(Data("secret-value".utf8), reference: reference)
        let data = try await store.read(reference)
        #expect(String(data: data!, encoding: .utf8) == "secret-value")
        try await store.delete(reference)
        #expect(try await store.read(reference) == nil)
    }
}
