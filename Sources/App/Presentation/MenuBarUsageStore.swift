import CursorBarDomain
import Foundation

/// UserDefaults for icon-only vs usage in the menu-bar extra. Defaults to usage.
struct MenuBarUsageStore {
    private let key = "menuBarUsageDisplay"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> MenuBarUsageDisplay {
        guard let raw = defaults.string(forKey: key),
              let display = MenuBarUsageDisplay(rawValue: raw)
        else {
            return .usage
        }
        return display
    }

    func save(_ display: MenuBarUsageDisplay) {
        defaults.set(display.rawValue, forKey: key)
    }
}
