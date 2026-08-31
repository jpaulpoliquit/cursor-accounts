import CursorBarDomain
import SwiftUI

struct StatusCapsule: View {
    let pill: SeatStatusPill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CursorProfilePill(title: pill.shortTitle)
            .animation(Motion.snappy(reduceMotion: reduceMotion), value: pill)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pill.explanation)
    }
}
