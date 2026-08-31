import Foundation

/// Owns which Keychain service names CursorBar may write. Cursor-owned names are forbidden.
public enum KeychainServicePolicy {
    public static let ownedServiceName = "app.cursorbar"
    /// Isolated test/harness writes only. Never the production service.
    public static let testServicePrefix = "app.cursorbar.test."

    public static let forbiddenCursorServiceNames: Set<String> = [
        "cursor-access-token",
        "cursor-refresh-token",
        "Cursor Safe Storage",
    ]

    public static func isWritable(_ serviceName: String) -> Bool {
        if forbiddenCursorServiceNames.contains(serviceName) { return false }
        if serviceName == ownedServiceName { return true }
        return serviceName.hasPrefix(testServicePrefix)
    }

    public static func assertWritable(_ serviceName: String) {
        precondition(
            isWritable(serviceName),
            "CursorBar may only write Keychain service \(ownedServiceName) or \(testServicePrefix)*"
        )
        precondition(
            !forbiddenCursorServiceNames.contains(serviceName),
            "Refusing to write Cursor-owned Keychain service"
        )
    }

    /// Production service is reserved for the real app. Tests must use a unique test service or memory store.
    public static func assertNotProductionServiceForTests(_ serviceName: String) {
        precondition(
            serviceName != ownedServiceName,
            "Tests must not write production Keychain service \(ownedServiceName)"
        )
        precondition(
            serviceName.hasPrefix(testServicePrefix),
            "Test Keychain service must start with \(testServicePrefix)"
        )
    }
}
