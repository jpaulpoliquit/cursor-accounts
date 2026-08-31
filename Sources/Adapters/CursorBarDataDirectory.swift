import Foundation

/// Application Support root for CursorBar caches. Tests and verify can override the path.
public enum CursorBarDataDirectory {
    public static func applicationSupportRoot(override: URL? = nil) -> URL {
        if let override {
            return override
        }
        if let path = ProcessInfo.processInfo.environment["CURSORBAR_APPLICATION_SUPPORT"],
           !path.isEmpty
        {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CursorBar", isDirectory: true)
    }
}
