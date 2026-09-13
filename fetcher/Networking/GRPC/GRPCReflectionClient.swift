import Foundation

struct GRPCReflectionClient: Sendable {
    var endpoint: String
    var tls: GRPCTLSConfiguration

    func listServices(metadata: [(String, String)] = []) async throws -> [String] {
        throw GRPCExecutionError.transport("Server reflection requires a live gRPC channel.")
    }

    func fileContainingSymbol(_ symbol: String, metadata: [(String, String)] = []) async throws -> Data {
        throw GRPCExecutionError.transport("Server reflection requires a live gRPC channel.")
    }

    func fetchDescriptorSet(metadata: [(String, String)] = []) async throws -> Data {
        let services = try await listServices(metadata: metadata)
        guard !services.isEmpty else {
            throw GRPCExecutionError.transport("Server reflection returned no services.")
        }

        var merged = Data()
        for service in services {
            let fileData = try await fileContainingSymbol(service, metadata: metadata)
            merged.append(fileData)
        }
        return merged
    }
}

enum GRPCReflectionMethod {
    static let listServices = "grpc.reflection.v1.ServerReflection/ServerReflectionInfo"
    static let fileContainingSymbol = "grpc.reflection.v1.ServerReflection/ServerReflectionInfo"
}

struct GRPCReflectionListServicesRequest: Sendable {
    var host: String
}

struct GRPCReflectionFileRequest: Sendable {
    var symbol: String
}
