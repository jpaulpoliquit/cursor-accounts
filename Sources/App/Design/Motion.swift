import SwiftUI

/// Motion tokens. Prefer cross-fades when Reduce Motion is on.
enum Motion {
    static func snappy(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 1.0)
    }

    static func gentle(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 1.0)
    }
}
