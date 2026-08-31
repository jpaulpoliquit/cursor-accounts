import CursorBarDomain
import Foundation
import Security

/// Non-interactive Keychain ACL probe for owned `app.cursorbar` items.
public enum OwnedKeychainAccess: Sendable {
    public enum ProbeResult: Sendable, Equatable {
        case readable
        case missing
        case accessDenied(OSStatus)
        case unexpected(OSStatus)
    }

    /// Probe without presenting Keychain UI. Safe for launch-path diagnosis.
    public static func probe(
        serviceName: String = KeychainServicePolicy.ownedServiceName,
        account: String
    ) -> ProbeResult {
        KeychainServicePolicy.assertWritable(serviceName)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return .readable
        case errSecItemNotFound:
            return .missing
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled, errSecWrPerm:
            return .accessDenied(status)
        default:
            return .unexpected(status)
        }
    }

    public static func anySeatAccessDenied(
        serviceName: String = KeychainServicePolicy.ownedServiceName
    ) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return false
        }
        if status == errSecAuthFailed || status == errSecInteractionNotAllowed
            || status == errSecUserCanceled || status == errSecWrPerm
        {
            return true
        }
        guard status == errSecSuccess, let rows = item as? [[String: Any]] else {
            return false
        }
        for row in rows {
            guard let account = row[kSecAttrAccount as String] as? String else { continue }
            guard account != KeychainAccountSwitchRecoveryJournal.accountName else { continue }
            if case .accessDenied = probe(serviceName: serviceName, account: account) {
                return true
            }
        }
        return false
    }
}
