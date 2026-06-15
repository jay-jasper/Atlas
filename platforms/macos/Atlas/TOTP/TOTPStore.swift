import Foundation
import Security

protocol TOTPStoring {
    func accounts() -> [TOTPAccount]
    func save(_ accounts: [TOTPAccount]) throws
    func add(_ account: TOTPAccount) throws
    func delete(id: UUID) throws
}

enum TOTPStoreError: LocalizedError, Equatable {
    case invalidAccount
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidAccount: return "Account requires an issuer and a valid base32 secret."
        case .keychain(let status): return "Keychain error (\(status))."
        }
    }
}

/// Stores TOTP accounts as a single JSON blob in the login Keychain.
final class KeychainTOTPStore: TOTPStoring {
    private let service: String
    private let account = "totp-accounts"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(service: String = "com.atlas.totp") {
        self.service = service
    }

    func accounts() -> [TOTPAccount] {
        guard let data = read() else { return [] }
        return (try? decoder.decode([TOTPAccount].self, from: data)) ?? []
    }

    func save(_ accounts: [TOTPAccount]) throws {
        guard accounts.allSatisfy(\.isValid) else { throw TOTPStoreError.invalidAccount }
        let data = try encoder.encode(accounts)
        try write(data)
    }

    func add(_ account: TOTPAccount) throws {
        guard account.isValid else { throw TOTPStoreError.invalidAccount }
        var current = accounts()
        current.append(account)
        try save(current)
    }

    func delete(id: UUID) throws {
        try save(accounts().filter { $0.id != id })
    }

    // MARK: - Keychain primitives

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read() -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private func write(_ data: Data) throws {
        let query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw TOTPStoreError.keychain(addStatus) }
            return
        }
        throw TOTPStoreError.keychain(updateStatus)
    }
}

/// In-memory store for tests and previews.
final class InMemoryTOTPStore: TOTPStoring {
    private var store: [TOTPAccount]
    init(accounts: [TOTPAccount] = []) { store = accounts }
    func accounts() -> [TOTPAccount] { store }
    func save(_ accounts: [TOTPAccount]) throws {
        guard accounts.allSatisfy(\.isValid) else { throw TOTPStoreError.invalidAccount }
        store = accounts
    }
    func add(_ account: TOTPAccount) throws {
        guard account.isValid else { throw TOTPStoreError.invalidAccount }
        store.append(account)
    }
    func delete(id: UUID) throws { store.removeAll { $0.id == id } }
}
