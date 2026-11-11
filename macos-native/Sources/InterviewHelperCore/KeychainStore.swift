import Foundation
import Security

public enum KeychainStore {
    public static let service = "com.interviewhelper.mac"
    private static let apiKeyAccount = "openai_api_key"

    /// Saved key, or `nil` when none is stored. `service` is overridable so tests use a throwaway item instead of the user's real key.
    public static func loadAPIKey(service: String = service) -> String? {
        var query = baseQuery(service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else {
            return nil
        }
        return key
    }

    /// Stores the trimmed key; a blank key deletes the saved one.
    public static func saveAPIKey(_ key: String, service: String = service) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteAPIKey(service: service)
            return
        }
        let query = baseQuery(service: service)
        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var add = query
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw keychainError(addStatus)
            }
        default:
            throw keychainError(updateStatus)
        }
    }

    public static func deleteAPIKey(service: String = service) throws {
        let status = SecItemDelete(baseQuery(service: service) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private static func baseQuery(service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
        ]
    }

    private static func keychainError(_ status: OSStatus) -> NSError {
        NSError(
            domain: "KeychainStore",
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: "Keychain error (\(status))."]
        )
    }
}
