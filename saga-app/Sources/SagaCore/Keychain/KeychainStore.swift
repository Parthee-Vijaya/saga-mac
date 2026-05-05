import Foundation
import OSLog
import Security

/// Generic helper til at læse/skrive sensitive strings (API-keys, tokens) i Keychain
/// under `kSecClassGenericPassword`. Bruges af ElevenLabs API-key og senere evt. cloud-LLM keys.
///
/// **Hvorfor ikke UserDefaults**: API-keys er secrets — Keychain er det rigtige sted.
/// `swift/security.md` rule kræver eksplicit at secrets ikke gemmes i UserDefaults.
public enum KeychainStore {
    private static let log = Logger(subsystem: "dk.parthee.saga", category: "keychain")
    private static let service = "dk.parthee.saga"

    /// Hent en string fra Keychain. Returnér nil hvis key ikke findes.
    public static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                log.warning("Keychain read \(key, privacy: .public) fejlede: \(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Skriv eller opdatér en string i Keychain. Tom string sletter posten.
    @discardableResult
    public static func write(_ value: String, for key: String) -> Bool {
        guard !value.isEmpty else {
            return delete(key)
        }
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        // Forsøg update først
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            log.warning("Keychain update \(key, privacy: .public) fejlede: \(updateStatus)")
            return false
        }

        // Posten findes ikke — add
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            log.warning("Keychain add \(key, privacy: .public) fejlede: \(addStatus)")
            return false
        }
        return true
    }

    /// Slet en post. Returnér true hvis slettet eller hvis posten ikke fandtes (idempotent).
    @discardableResult
    public static func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// True hvis posten findes (uden at læse værdien).
    public static func exists(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
}

/// Eksplicitte navngivne keys, så vi undgår string-typos spredt i koden.
public enum KeychainKey {
    public static let elevenLabsAPI = "elevenlabs.api_key"
}
