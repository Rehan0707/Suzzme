import SwiftUI

/// One restrained glass layer for focus surfaces. Older systems get native
/// material; Reduce Transparency gets an opaque, high-contrast fallback.
struct SuzzmeGlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    var tint: Color? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(SuzzmeTheme.backgroundSecondary, in: shape)
                .overlay(shape.strokeBorder(SuzzmeTheme.separator, lineWidth: 1))
        } else if #available(iOS 26, macOS 26, *) {
            content
                .glassEffect(.regular.tint(tint), in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay {
                    shape.fill((tint ?? .clear).opacity(0.035))
                        .allowsHitTesting(false)
                }
                .overlay(shape.strokeBorder(SuzzmeTheme.separator, lineWidth: 1))
        }
    }
}

extension View {
    func suzzmeGlassSurface(cornerRadius: CGFloat = SuzzmeTheme.Radius.largeSurface,
                            tint: Color? = nil) -> some View {
        modifier(SuzzmeGlassSurface(cornerRadius: cornerRadius, tint: tint))
    }
}
