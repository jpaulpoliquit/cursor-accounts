import CursorBarDomain
import Foundation
import Security

/// Exact prior auth rows + minimal metadata for crash-safe switch rollback.
/// Descriptions never include secrets, email, or blob bytes.
public struct PendingAccountSwitchRecovery: Sendable, Equatable {
    public static let currentSchemaVersion = PendingAccountSwitchRecoveryRef.currentSchemaVersion

    public let schemaVersion: Int
    public let seatID: SeatID
    public let generation: UInt64
    public let createdAt: Date
    public let backup: AuthRowBackup

    public init(
        schemaVersion: Int = currentSchemaVersion,
        seatID: SeatID,
        generation: UInt64,
        createdAt: Date = Date(),
        backup: AuthRowBackup
    ) {
        self.schemaVersion = schemaVersion
        self.seatID = seatID
        self.generation = generation
        self.createdAt = createdAt
        self.backup = backup
    }

    public var recoveryRef: PendingAccountSwitchRecoveryRef {
        PendingAccountSwitchRecoveryRef(
            schemaVersion: schemaVersion,
            seatID: seatID,
            generation: generation
        )
    }

    public var switchContext: SwitchContext {
        SwitchContext(seatID: seatID, generation: generation)
    }
}

extension PendingAccountSwitchRecovery: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        "PendingAccountSwitchRecovery(v\(schemaVersion), seat=\(seatID.displayIndex), gen=\(generation), rows=\(backup.rows.count))"
    }

    public var debugDescription: String { description }
}

public enum AccountSwitchRecoveryJournalError: Error, Sendable, Equatable {
    case alreadyExists
    case notFound
    case corrupt
    case encodeFailed
    case keychain(OSStatus)
    case accessDenied(OSStatus)
}

extension AccountSwitchRecoveryJournalError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .alreadyExists: "Recovery journal already exists"
        case .notFound: "Recovery journal missing"
        case .corrupt: "Recovery journal corrupt or unreadable"
        case .encodeFailed: "Recovery journal encode failed"
        case .keychain(let status): "Recovery journal Keychain error (\(status))"
        case .accessDenied(let status): "Recovery journal Keychain access denied (\(status))"
        }
    }
}

/// At most one durable pending recovery journal.
public protocol AccountSwitchRecoveryJournaling: Sendable {
    func load() throws -> PendingAccountSwitchRecovery?
    /// Fails with `.alreadyExists` when a journal is already present.
    func save(_ recovery: PendingAccountSwitchRecovery) throws
    func clear() throws
    func hasPending() throws -> Bool
}

/// In-memory journal for tests. Survives across engine instances when shared.
public final class MemoryAccountSwitchRecoveryJournal: AccountSwitchRecoveryJournaling, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: PendingAccountSwitchRecovery?
    private var corruptOnLoad = false
    private var failHasPending: AccountSwitchRecoveryJournalError?
    private var failLoad: AccountSwitchRecoveryJournalError?
    private var failClear: AccountSwitchRecoveryJournalError?

    public init(initial: PendingAccountSwitchRecovery? = nil) {
        self.stored = initial
    }

    public func configureFailures(
        hasPending: AccountSwitchRecoveryJournalError? = nil,
        load: AccountSwitchRecoveryJournalError? = nil,
        clear: AccountSwitchRecoveryJournalError? = nil
    ) {
        lock.lock()
        defer { lock.unlock() }
        failHasPending = hasPending
        failLoad = load
        failClear = clear
    }

    public func markCorruptOnLoad() {
        lock.lock()
        defer { lock.unlock() }
        corruptOnLoad = true
    }

    public func load() throws -> PendingAccountSwitchRecovery? {
        lock.lock()
        defer { lock.unlock() }
        if let failLoad {
            throw failLoad
        }
        if corruptOnLoad, stored != nil {
            throw AccountSwitchRecoveryJournalError.corrupt
        }
        return stored
    }

    public func save(_ recovery: PendingAccountSwitchRecovery) throws {
        lock.lock()
        defer { lock.unlock() }
        if stored != nil {
            throw AccountSwitchRecoveryJournalError.alreadyExists
        }
        stored = recovery
        corruptOnLoad = false
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }
        if let failClear {
            throw failClear
        }
        stored = nil
        corruptOnLoad = false
    }

    public func hasPending() throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let failHasPending {
            throw failHasPending
        }
        // Presence only: corrupt payloads still block new switches until resolved.
        return stored != nil
    }
}

/// CursorBar-owned Keychain journal. Never writes Cursor-owned services.
public struct KeychainAccountSwitchRecoveryJournal: AccountSwitchRecoveryJournaling {
    public static let accountName = "pending-account-switch-recovery"

    private let serviceName: String

    public init(serviceName: String = KeychainServicePolicy.ownedServiceName) {
        KeychainServicePolicy.assertWritable(serviceName)
        self.serviceName = serviceName
    }

    public func load() throws -> PendingAccountSwitchRecovery? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: Self.accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        if Self.isAccessDenied(status) {
            throw AccountSwitchRecoveryJournalError.accessDenied(status)
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw AccountSwitchRecoveryJournalError.keychain(status)
        }
        do {
            let payload = try JSONDecoder().decode(JournalPayload.self, from: data)
            return try payload.makeRecovery()
        } catch {
            throw AccountSwitchRecoveryJournalError.corrupt
        }
    }

    public func save(_ recovery: PendingAccountSwitchRecovery) throws {
        KeychainServicePolicy.assertWritable(serviceName)
        if try hasPending() {
            throw AccountSwitchRecoveryJournalError.alreadyExists
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(JournalPayload(recovery: recovery))
        } catch {
            throw AccountSwitchRecoveryJournalError.encodeFailed
        }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: Self.accountName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            throw AccountSwitchRecoveryJournalError.alreadyExists
        }
        if Self.isAccessDenied(status) {
            throw AccountSwitchRecoveryJournalError.accessDenied(status)
        }
        guard status == errSecSuccess else {
            throw AccountSwitchRecoveryJournalError.keychain(status)
        }
    }

    public func clear() throws {
        KeychainServicePolicy.assertWritable(serviceName)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: Self.accountName,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound || status == errSecSuccess {
            return
        }
        if Self.isAccessDenied(status) {
            throw AccountSwitchRecoveryJournalError.accessDenied(status)
        }
        throw AccountSwitchRecoveryJournalError.keychain(status)
    }

    public func hasPending() throws -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: Self.accountName,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound {
            return false
        }
        if Self.isAccessDenied(status) {
            throw AccountSwitchRecoveryJournalError.accessDenied(status)
        }
        guard status == errSecSuccess else {
            throw AccountSwitchRecoveryJournalError.keychain(status)
        }
        return true
    }

    private static func isAccessDenied(_ status: OSStatus) -> Bool {
        switch status {
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled, errSecWrPerm:
            return true
        default:
            return false
        }
    }
}

private struct JournalPayload: Codable {
    var schemaVersion: Int
    var seatID: String
    var generation: UInt64
    var createdAt: Date
    var backup: AuthRowBackup

    init(recovery: PendingAccountSwitchRecovery) {
        schemaVersion = recovery.schemaVersion
        seatID = recovery.seatID.rawValue
        generation = recovery.generation
        createdAt = recovery.createdAt
        backup = recovery.backup
    }

    func makeRecovery() throws -> PendingAccountSwitchRecovery {
        guard schemaVersion == PendingAccountSwitchRecovery.currentSchemaVersion else {
            throw AccountSwitchRecoveryJournalError.corrupt
        }
        guard let seatID = SeatID(rawValue: seatID) else {
            throw AccountSwitchRecoveryJournalError.corrupt
        }
        return PendingAccountSwitchRecovery(
            schemaVersion: schemaVersion,
            seatID: seatID,
            generation: generation,
            createdAt: createdAt,
            backup: backup
        )
    }
}
