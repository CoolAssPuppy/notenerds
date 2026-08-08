import Security
import XCTest
@testable import NoteNerds

final class NotionCredentialStoreBehaviorTests: XCTestCase {
    func testKeychainStoreSavesReplacesLoadsAndDeletesOneConnection() throws {
        let service = "com.strategicnerds.notenerds.tests.\(UUID().uuidString)"
        let store = KeychainNotionCredentialStore(service: service)
        defer { try? store.delete() }
        let initial = NotionStoredConnection.fixture(accessToken: "first", refreshToken: "refresh-one")
        let replacement = NotionStoredConnection.fixture(accessToken: "second", refreshToken: "refresh-two")

        XCTAssertNil(try store.load())
        try store.save(initial)
        XCTAssertEqual(try store.load(), initial)
        try store.save(replacement)
        XCTAssertEqual(try store.load(), replacement)
        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testKeychainCredentialsStayOnThisDeviceAndAreAvailableAfterFirstUnlock() throws {
        let service = "com.strategicnerds.notenerds.tests.\(UUID().uuidString)"
        let store = KeychainNotionCredentialStore(service: service)
        defer { try? store.delete() }
        try store.save(.fixture())
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: KeychainNotionCredentialStore.account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?

        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &item), errSecSuccess)
        let attributes = try XCTUnwrap(item as? [String: Any])
        XCTAssertEqual(
            attributes[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
        XCTAssertNil(attributes[kSecValueData as String])
    }
}

private extension NotionStoredConnection {
    static func fixture(
        accessToken: String = "access",
        refreshToken: String = "refresh"
    ) -> NotionStoredConnection {
        NotionStoredConnection(
            credentials: NotionOAuthCredentials(
                accessToken: accessToken,
                refreshToken: refreshToken,
                workspaceID: "workspace-id",
                workspaceName: "Strategic Nerds",
                workspaceIcon: nil,
                botID: "bot-id"
            ),
            connectedAt: DomainFixtures.fixedDate
        )
    }
}
