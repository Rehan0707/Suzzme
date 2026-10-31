import SwiftUI

// Test-only exact extraction from Platform/macOS/MacAssistantPresence.swift.
// This proves six pure path bounds assertions, not Mac notch/window runtime.
#if os(iOS)
struct SuzzmeNotchSurfaceShape: Shape {
    var attached: Bool
    var neckWidth: CGFloat
    var topCornerRadius: CGFloat = 8
    var bottomCornerRadius: CGFloat = 18

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard isValid(rect) else { return Path() }
        guard attached else { return RoundedRectangle(cornerRadius: 24, style: .continuous).path(in: rect) }
        var path = skirtPath(in: rect)
        path.closeSubpath()
        return path
    }

    /// Open skirt: concave top corners, sides and rounded bottom. Its endpoints
    /// touch the display edge; the flat bezel line remains deliberately dark.
    func skirtPath(in rect: CGRect) -> Path {
        guard isValid(rect) else { return Path() }
        guard attached else { return RoundedRectangle(cornerRadius: 24, style: .continuous).path(in: rect) }
        let neck = min(nonnegative(neckWidth), rect.width)
        let top = min(nonnegative(topCornerRadius), rect.height, (rect.width - neck) / 2)
        let bottom = min(nonnegative(bottomCornerRadius), rect.width / 2 - top, rect.height - top)
        let bodyTop = rect.minY
        let left = rect.minX + top
        let right = rect.maxX - top
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: bodyTop))
        path.addQuadCurve(to: CGPoint(x: left, y: bodyTop + top), control: CGPoint(x: left, y: bodyTop))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: left + bottom, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - bottom), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: bodyTop + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: bodyTop), control: CGPoint(x: right, y: bodyTop))
        return path
    }

    private func nonnegative(_ value: CGFloat) -> CGFloat { value.isFinite ? max(0, value) : 0 }

    private func isValid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite
            && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
            && rect.maxX.isFinite && rect.maxY.isFinite
            && rect.size.width > 0 && rect.size.height > 0
    }
}
#endif
