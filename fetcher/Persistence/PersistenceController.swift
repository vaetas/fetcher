import Foundation
import SwiftData

enum PersistenceController {
    static let sharedModelContainer: ModelContainer = {
        do {
            return try makeContainer(inMemory: false)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let schema = Schema([
            ProjectRecord.self,
            RequestRecord.self,
            RESTRequestRecord.self,
            GraphQLRequestRecord.self,
            GRPCRequestRecord.self,
            APIDefinitionRecord.self,
            RequestParameterRecord.self,
            RequestAuthRecord.self,
            EnvironmentRecord.self,
            EnvironmentVariableRecord.self,
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
