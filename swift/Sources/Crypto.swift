import Foundation
import CryptoKit
import Security

final class Crypto {
    static let shared = Crypto()

    private let service = "com.paster.clipboard.dbkey"
    private let account: String = NSUserName()
    private let prefix = "v1:"
    private var key: SymmetricKey

    private init() {
        if let existing = Self.readKey(service: "com.paster.clipboard.dbkey", account: NSUserName()) {
            self.key = SymmetricKey(data: existing)
        } else {
            let new = SymmetricKey(size: .bits256)
            let data = new.withUnsafeBytes { Data($0) }
            Self.writeKey(data, service: "com.paster.clipboard.dbkey", account: NSUserName())
            self.key = new
        }
    }

    func encrypt(_ plaintext: String) -> String? {
        guard let data = plaintext.data(using: .utf8) else { return nil }
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { return nil }
            return prefix + combined.base64EncodedString()
        } catch {
            return nil
        }
    }

    func decrypt(_ token: String) -> String? {
        guard token.hasPrefix(prefix) else { return nil }
        let b64 = String(token.dropFirst(prefix.count))
        guard let data = Data(base64Encoded: b64) else { return nil }
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            let opened = try AES.GCM.open(box, using: key)
            return String(data: opened, encoding: .utf8)
        } catch {
            return nil
        }
    }

    func encryptData(_ data: Data) -> Data? {
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            return sealed.combined
        } catch {
            return nil
        }
    }

    func decryptData(_ data: Data) -> Data? {
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(box, using: key)
        } catch {
            return nil
        }
    }

    private static func readKey(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func writeKey(_ data: Data, service: String, account: String) {
        let delete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(delete as CFDictionary)

        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(add as CFDictionary, nil)
    }
}
