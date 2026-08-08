import Foundation
import Security

protocol NotionCredentialStore: Sendable {
    func load() throws -> NotionStoredConnection?
    func save(_ connection: NotionStoredConnection) throws
    func delete() throws
}

enum NotionCredentialStoreError: Error, Equatable, Sendable {
    case keychain(OSStatus)
    case invalidData
}

struct KeychainNotionCredentialStore: NotionCredentialStore, Sendable {
    static let account = "active-notion-connection"

    private let service: String

    init(service: String = "com.strategicnerds.notenerds.notion") {
        self.service = service
    }

    func load() throws -> NotionStoredConnection? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw NotionCredentialStoreError.keychain(status)
        }
        guard let data = item as? Data else {
            throw NotionCredentialStoreError.invalidData
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        do {
            return try decoder.decode(NotionStoredConnection.self, from: data)
        } catch {
            throw NotionCredentialStoreError.invalidData
        }
    }

    func save(_ connection: NotionStoredConnection) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(connection)
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw NotionCredentialStoreError.keychain(updateStatus)
        }
        var item = baseQuery
        values.forEach { item[$0.key] = $0.value }
        item[kSecAttrSynchronizable as String] = false
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NotionCredentialStoreError.keychain(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NotionCredentialStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account
        ]
    }
}
