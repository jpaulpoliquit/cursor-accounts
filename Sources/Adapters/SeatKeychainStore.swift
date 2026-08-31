import CursorBarDomain
import Foundation
import Security

/// Reads and writes only `app.cursorbar` Keychain items. Never touches Cursor-owned services.
public struct SeatKeychainStore: Sendable {
    public enum StoreError: Error, Sendable, Equatable {
        case unexpectedStatus(OSStatus)
        case accessDenied(OSStatus)
        case decodeFailed
        case encodeFailed
    }

    private let serviceName: String

    public init(serviceName: String = KeychainServicePolicy.ownedServiceName) {
        KeychainServicePolicy.assertWritable(serviceName)
        self.serviceName = serviceName
    }

    public func loadAll() throws -> [StoredSeatRecord] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return []
        }
        if Self.isAccessDenied(status) {
            throw StoreError.accessDenied(status)
        }
        guard status == errSecSuccess, let rows = item as? [[String: Any]] else {
            throw StoreError.unexpectedStatus(status)
        }
        return rows.compactMap { row in
            guard let account = row[kSecAttrAccount as String] as? String else { return nil }
            guard account != KeychainAccountSwitchRecoveryJournal.accountName else { return nil }
            guard let seatID = SeatID(rawValue: account) else { return nil }
            return try? load(seatID: seatID)
        }
    }

    public func load(seatID: SeatID) throws -> StoredSeatRecord? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: seatID.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // Never present password UI on read; migrator repairs stale ACL instead.
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        if Self.isAccessDenied(status) {
            throw StoreError.accessDenied(status)
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw StoreError.unexpectedStatus(status)
        }
        return try decode(data, seatID: seatID)
    }

    public func save(_ record: StoredSeatRecord) throws {
        KeychainServicePolicy.assertWritable(serviceName)
        let data = try encode(record)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: record.seatID.rawValue,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        let existing = SecItemCopyMatching(query as CFDictionary, nil)
        if existing == errSecSuccess {
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if Self.isAccessDenied(status) { throw StoreError.accessDenied(status) }
            guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
            return
        }
        if Self.isAccessDenied(existing) {
            // Stale ACL blocks update. Delete then add under current code signature.
            try delete(seatID: record.seatID)
        } else if existing != errSecItemNotFound && existing != errSecSuccess {
            throw StoreError.unexpectedStatus(existing)
        }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: record.seatID.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try delete(seatID: record.seatID)
            status = SecItemAdd(add as CFDictionary, nil)
        }
        if Self.isAccessDenied(status) { throw StoreError.accessDenied(status) }
        guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
    }

    public func delete(seatID: SeatID) throws {
        KeychainServicePolicy.assertWritable(serviceName)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: seatID.rawValue,
            // Never present password UI; caller surfaces a repair path instead.
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound || status == errSecSuccess {
            return
        }
        if Self.isAccessDenied(status) {
            throw StoreError.accessDenied(status)
        }
        throw StoreError.unexpectedStatus(status)
    }

    private static func isAccessDenied(_ status: OSStatus) -> Bool {
        switch status {
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled, errSecWrPerm:
            return true
        default:
            return false
        }
    }

    private func encode(_ record: StoredSeatRecord) throws -> Data {
        let payload = KeychainPayload(
            identity: record.identity,
            access: record.access.rawValue,
            refresh: record.refresh.rawValue,
            email: record.email?.value,
            displayName: record.displayName?.value,
            expiresAt: record.expiresAt,
            membershipType: record.membershipType,
            subscriptionStatus: record.subscriptionStatus,
            apiKey: record.apiKey?.rawValue
        )
        do {
            return try JSONEncoder().encode(payload)
        } catch {
            throw StoreError.encodeFailed
        }
    }

    private func decode(_ data: Data, seatID: SeatID) throws -> StoredSeatRecord {
        let payload: KeychainPayload
        do {
            payload = try JSONDecoder().decode(KeychainPayload.self, from: data)
        } catch {
            throw StoreError.decodeFailed
        }
        guard let access = AccessToken(payload.access),
              let refresh = RefreshToken(payload.refresh)
        else {
            throw StoreError.decodeFailed
        }
        let apiKey = payload.apiKey.flatMap(APIKey.init)
        return StoredSeatRecord(
            seatID: seatID,
            identity: payload.identity,
            access: access,
            refresh: refresh,
            email: payload.email.flatMap(Email.init),
            displayName: payload.displayName.flatMap(DisplayName.init),
            expiresAt: payload.expiresAt,
            membershipType: payload.membershipType,
            subscriptionStatus: payload.subscriptionStatus,
            apiKey: apiKey
        )
    }
}

private struct KeychainPayload: Codable, Sendable {
    var identity: SessionIdentity
    var access: String
    var refresh: String
    var email: String?
    var displayName: String?
    var expiresAt: Date?
    var membershipType: String?
    var subscriptionStatus: String?
    var apiKey: String?
}

extension SeatKeychainStore.StoreError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unexpectedStatus(let status): "Keychain error (\(status))"
        case .accessDenied(let status): "Keychain access denied (\(status))"
        case .decodeFailed: "Keychain payload decode failed"
        case .encodeFailed: "Keychain payload encode failed"
        }
    }
}
