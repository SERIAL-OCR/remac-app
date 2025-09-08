import Foundation
import Security

enum SecureStoreError: Error {
    case unexpectedStatus(OSStatus)
    case dataConversionFailed
}

struct SecureStore {
    static func set(_ value: String, forKey key: String, service: String = Bundle.main.bundleIdentifier ?? "com.appleserialscanner") throws {
        guard let data = value.data(using: .utf8) else { throw SecureStoreError.dataConversionFailed }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else { throw SecureStoreError.unexpectedStatus(status) }
    }

    static func get(forKey key: String, service: String = Bundle.main.bundleIdentifier ?? "com.appleserialscanner") throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecureStoreError.unexpectedStatus(status) }

        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw SecureStoreError.dataConversionFailed
        }
        return string
    }

    static func remove(forKey key: String, service: String = Bundle.main.bundleIdentifier ?? "com.appleserialscanner") throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.unexpectedStatus(status)
        }
    }
}

