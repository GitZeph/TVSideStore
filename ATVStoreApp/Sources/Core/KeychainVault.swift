import Foundation
import Security

/// Thread-safe wrapper around tvOS Security.framework Keychain services.
/// Critical on tvOS because NSDocumentDirectory is inaccessible and Caches can be purged.
public final class KeychainVault {
    public static let shared = KeychainVault()

    private let serviceIdentifier = "com.atvstore.SideStoreTV.keychain"

    // Storage Keys
    public static let keyPairingFile = "atv_pairing_file"
    public static let keyCertificateP12 = "atv_cert_p12"
    public static let keyGSASessionToken = "atv_gsa_session_token"
    public static let keyAppleID = "atv_apple_id"
    public static let keyAppRegistryBackup = "atv_app_registry_backup"

    private init() {}

    // MARK: - Core Keychain Operations

    public func save(key: String, data: Data) throws {
        // Prepare query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        // First attempt to delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "SecItemAdd failed with status: \(status)"]
            )
        }
    }

    public func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return data
    }

    public func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Dedicated Domain Helpers

    // Pairing File (.mobiledevicepairing / RPPairing)
    public func savePairingFile(_ data: Data) throws {
        try save(key: Self.keyPairingFile, data: data)
    }

    public func loadPairingFile() -> Data? {
        return load(key: Self.keyPairingFile)
    }

    public func hasPairingFile() -> Bool {
        return loadPairingFile() != nil
    }

    public func deletePairingFile() {
        delete(key: Self.keyPairingFile)
    }

    // Development Certificate (.p12 base64)
    public func saveCertificate(_ p12Base64: String) throws {
        guard let data = p12Base64.data(using: .utf8) else { return }
        try save(key: Self.keyCertificateP12, data: data)
    }

    public func loadCertificate() -> String? {
        guard let data = load(key: Self.keyCertificateP12) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // GSA Session & Apple ID
    public func saveGSASession(token: String, appleID: String) throws {
        if let tokenData = token.data(using: .utf8) {
            try save(key: Self.keyGSASessionToken, data: tokenData)
        }
        if let idData = appleID.data(using: .utf8) {
            try save(key: Self.keyAppleID, data: idData)
        }
    }

    public func loadGSASession() -> (token: String, appleID: String)? {
        guard let tokenData = load(key: Self.keyGSASessionToken),
              let token = String(data: tokenData, encoding: .utf8),
              let idData = load(key: Self.keyAppleID),
              let appleID = String(data: idData, encoding: .utf8) else {
            return nil
        }
        return (token, appleID)
    }

    public func deleteGSASession() {
        delete(key: Self.keyGSASessionToken)
        delete(key: Self.keyAppleID)
    }

    // App Registry Backup (<250KB)
    public func saveAppRegistryBackup(_ jsonData: Data) throws {
        try save(key: Self.keyAppRegistryBackup, data: jsonData)
    }

    public func loadAppRegistryBackup() -> Data? {
        return load(key: Self.keyAppRegistryBackup)
    }

    public func clearAll() {
        delete(key: Self.keyPairingFile)
        delete(key: Self.keyCertificateP12)
        delete(key: Self.keyGSASessionToken)
        delete(key: Self.keyAppleID)
        delete(key: Self.keyAppRegistryBackup)
    }
}

