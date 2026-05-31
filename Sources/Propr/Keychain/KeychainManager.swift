import Foundation
import Security

/// Securely stores API keys in the macOS Keychain.
/// Keys are never stored in UserDefaults, files, or anywhere else.
@MainActor
final class KeychainManager {
    static let shared = KeychainManager()
    
    private let service = "com.tharuxpert.Propr.llm-keys"
    
    private init() {}
    
    /// Stores or updates an API key for a given endpoint ID.
    func saveAPIKey(_ key: String, for endpointID: UUID) throws {
        let account = endpointID.uuidString
        
        guard let data = key.data(using: .utf8) else {
            throw KeychainError.invalidData
        }
        
        // Delete any existing item first (allows update)
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrLabel as String: "Propr LLM Key - \(account)"
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    /// Retrieves the API key for an endpoint (if stored).
    func apiKey(for endpointID: UUID) throws -> String? {
        let account = endpointID.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecItemNotFound {
            return nil
        }
        
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedStatus(status)
        }
        
        return key
    }
    
    /// Deletes the API key for an endpoint.
    func deleteAPIKey(for endpointID: UUID) {
        let account = endpointID.uuidString
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    enum KeychainError: Error, LocalizedError {
        case unexpectedStatus(OSStatus)
        case invalidData
        
        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                return "Keychain operation failed with status \(status)"
            case .invalidData:
                return "Could not encode API key"
            }
        }
    }
}