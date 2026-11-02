import Foundation
import Security

/// Per-device password storage in the iOS Keychain.
///
/// We generate and custodied our own 32-byte device password (see `Recovery`), exactly as the
/// official app did (`docs/protocol/pairing.md`). Losing it means running the reset-challenge
/// recovery again (which needs a cold reboot of the ring), so it can optionally be synced through
/// **iCloud Keychain** (`kSecAttrSynchronizable`) and can be shown/copied in Settings › Advanced.
///
/// Keyed by the CoreBluetooth peripheral identifier. That identifier is per-iPhone, so on another
/// iPhone a synced password arrives under a different account: `DeviceController` then tries the
/// other stored passwords (`otherPasswords(excluding:)`) and re-saves the one that works.
enum KeychainStore {

    private static let service = "com.sh2.smarthalo2.devicePassword"

    enum KeychainError: Error { case unexpectedStatus(OSStatus) }

    private static func baseQuery(_ deviceID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID,
        ]
    }

    /// Store (or replace) the password for a device. `synchronizable` puts it in iCloud Keychain.
    static func save(password: String, deviceID: String, synchronizable: Bool) throws {
        try add(Data(password.utf8), deviceID: deviceID, synchronizable: synchronizable)
        // The new copy is in place; now drop the copy with the other sync flag, if any.
        delete(deviceID: deviceID, synchronizable: !synchronizable)
    }

    /// Load the password for a device (synced or local copy), or nil if none stored.
    static func load(deviceID: String) -> String? {
        var query = baseQuery(deviceID)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete the stored password for a device (both the synced and the local copy).
    static func delete(deviceID: String) {
        var query = baseQuery(deviceID)
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(query as CFDictionary)
    }

    /// Passwords stored for OTHER peripheral identifiers (e.g. synced from another iPhone), unique.
    static func otherPasswords(excluding deviceID: String) -> [String] {
        var seen = Set<String>()
        return entries()
            .filter { $0.account != deviceID }
            .compactMap { load(account: $0.account, synchronizable: $0.synchronizable) }
            .filter { seen.insert($0).inserted }
    }

    /// Move every stored password to (or out of) iCloud Keychain. Copy-then-delete, so a failure
    /// never loses the only copy.
    static func applySync(_ synchronizable: Bool) {
        for entry in entries() where entry.synchronizable != synchronizable {
            guard let password = load(account: entry.account, synchronizable: entry.synchronizable),
                  (try? add(Data(password.utf8), deviceID: entry.account, synchronizable: synchronizable)) != nil
            else { continue }
            delete(deviceID: entry.account, synchronizable: entry.synchronizable)
        }
    }

    // MARK: - Private

    private static func add(_ data: Data, deviceID: String, synchronizable: Bool) throws {
        delete(deviceID: deviceID, synchronizable: synchronizable)
        var attributes = baseQuery(deviceID)
        attributes[kSecValueData as String] = data
        // Synchronizable items can't be "ThisDeviceOnly"; AfterFirstUnlock works for both.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        attributes[kSecAttrSynchronizable as String] = synchronizable
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    private static func delete(deviceID: String, synchronizable: Bool) {
        var query = baseQuery(deviceID)
        query[kSecAttrSynchronizable as String] = synchronizable
        SecItemDelete(query as CFDictionary)
    }

    private static func load(account: String, synchronizable: Bool) -> String? {
        var query = baseQuery(account)
        query[kSecAttrSynchronizable as String] = synchronizable
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Every stored password item (attributes only), synced or local.
    private static func entries() -> [(account: String, synchronizable: Bool)] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let list = items as? [[String: Any]] else { return [] }
        return list.compactMap { attrs in
            guard let account = attrs[kSecAttrAccount as String] as? String else { return nil }
            let sync = (attrs[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue ?? false
            return (account, sync)
        }
    }
}
