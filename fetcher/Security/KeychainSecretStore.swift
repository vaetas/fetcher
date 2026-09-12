import Foundation
import Security

protocol SecretStore: Sendable {
    func read(_ reference: SecretReference) async throws -> Data?
    func write(_ data: Data, reference: SecretReference) async throws
    func delete(_ reference: SecretReference) async throws
}

actor KeychainSecretStore: SecretStore {
    private let service: String

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "dev.pavlovsky.fetcher") {
        self.service = "\(bundleIdentifier).secret"
    }

    func read(_ reference: SecretReference) async throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference.id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func write(_ data: Data, reference: SecretReference) async throws {
        try await delete(reference)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference.id.uuidString,
            kSecAttrLabel as String: reference.label,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func delete(_ reference: SecretReference) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference.id.uuidString,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

enum KeychainError: Error, Sendable {
    case unexpectedStatus(OSStatus)
}
