import Foundation
import Synchronization
import Security

/// Stores small secrets as generic passwords in the user's login keychain.
///
/// The protocol exists so tests and previews never touch the real keychain.
protocol SecretStoring: Sendable {
    func data(for key: String) throws -> Data?
    func set(_ data: Data, for key: String) throws
    func remove(_ key: String) throws
}

extension SecretStoring {
    func value<Value: Decodable>(_ type: Value.Type, for key: String) -> Value? {
        guard let data = try? data(for: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func setValue(_ value: some Encodable, for key: String) throws {
        try set(JSONEncoder().encode(value), for: key)
    }
}

struct KeychainStore: SecretStoring {
    let service: String

    init(service: String = "org.panespace.cloud") {
        self.service = service
    }

    func data(for key: String) throws -> Data? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func set(_ data: Data, for key: String) throws {
        let query = baseQuery(for: key)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func remove(_ key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

struct KeychainError: LocalizedError, Equatable {
    let status: OSStatus

    var errorDescription: String? {
        L10n.text("PaneSpace could not access the keychain.")
    }
}

/// Keeps secrets in memory, for tests.
final class InMemorySecretStore: SecretStoring {
    private let values = Mutex<[String: Data]>([:])

    func data(for key: String) throws -> Data? {
        values.withLock { $0[key] }
    }

    func set(_ data: Data, for key: String) throws {
        values.withLock { $0[key] = data }
    }

    func remove(_ key: String) throws {
        _ = values.withLock { $0.removeValue(forKey: key) }
    }
}
