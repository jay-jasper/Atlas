import CryptoKit
import Foundation
import Security

enum SecureLocalDataError: Error {
    case keychain(OSStatus)
    case invalidCiphertext
}

/// Encrypts privacy-sensitive local payloads with an AES key kept in Keychain.
final class SecureLocalData: @unchecked Sendable {
    static let shared = SecureLocalData()

    private let service = "ai.atlas.secure-local-data"
    private let account = "content-key-v1"
    private let marker = Data("ATLAS-SEALED-1\n".utf8)
    private let lock = NSLock()
    private var cachedKey: SymmetricKey?

    func seal(_ plaintext: Data) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key())
        guard let combined = box.combined else { throw SecureLocalDataError.invalidCiphertext }
        return marker + combined
    }

    func open(_ stored: Data) throws -> Data {
        guard stored.starts(with: marker) else { return stored } // migrate legacy plaintext on next write
        let combined = stored.dropFirst(marker.count)
        let box = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(box, using: key())
    }

    private func key() throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        if let cachedKey { return cachedKey }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            let key = SymmetricKey(data: data)
            cachedKey = key
            return key
        }
        guard status == errSecItemNotFound else { throw SecureLocalDataError.keychain(status) }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let insert: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        let insertStatus = SecItemAdd(insert as CFDictionary, nil)
        guard insertStatus == errSecSuccess || insertStatus == errSecDuplicateItem else {
            throw SecureLocalDataError.keychain(insertStatus)
        }
        cachedKey = key
        return key
    }
}

enum SensitiveClipboardFilter {
    static func shouldExclude(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let secretLabels = ["password:", "password=", "passcode:", "api_key=", "api-key:", "secret="]
        if secretLabels.contains(where: lowered.contains) { return true }
        if lowered.contains("verification code") || lowered.contains("one-time code") { return true }
        let digits = text.filter(\.isNumber)
        return (13...19).contains(digits.count) && passesLuhn(digits)
    }

    private static func passesLuhn(_ digits: String) -> Bool {
        let values = digits.reversed().compactMap(\.wholeNumberValue)
        let sum = values.enumerated().reduce(0) { total, pair in
            let (index, value) = pair
            if index.isMultiple(of: 2) { return total + value }
            let doubled = value * 2
            return total + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum.isMultiple(of: 10)
    }
}
