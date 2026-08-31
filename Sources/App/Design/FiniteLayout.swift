import CoreGraphics

/// SwiftUI `.frame` rejects NaN and negatives. ChartProxy often returns NaN, not nil.
enum FiniteLayout {
    static func dimension(_ value: CGFloat) -> CGFloat? {
        guard value.isFinite, value >= 0 else { return nil }
        return value
    }

    static func point(x: CGFloat, y: CGFloat) -> CGPoint? {
        guard x.isFinite, y.isFinite else { return nil }
        return CGPoint(x: x, y: y)
    }

    static func rect(_ rect: CGRect) -> CGRect? {
        // `CGRect.width` is abs(size.width). Frame modifiers need the raw size.
        guard dimension(rect.size.width) != nil, dimension(rect.size.height) != nil,
              rect.origin.x.isFinite, rect.origin.y.isFinite
        else { return nil }
        return rect
    }
}
