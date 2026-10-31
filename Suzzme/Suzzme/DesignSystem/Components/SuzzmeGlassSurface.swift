import SwiftUI

/// One restrained glass layer for focus surfaces. Older systems get native
/// material; Reduce Transparency gets an opaque, high-contrast fallback.
struct SuzzmeGlassControlSurface: ViewModifier {
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
    func suzzmeGlassControlSurface(cornerRadius: CGFloat = SuzzmeTheme.Radius.largeSurface,
                                   tint: Color? = nil) -> some View {
        modifier(SuzzmeGlassControlSurface(cornerRadius: cornerRadius, tint: tint))
    }

    /// Opaque content-layer surface. Liquid Glass is reserved for controls and
    /// navigation; cards and information stay on a quiet, readable plane.
    func suzzmeContentSurface(cornerRadius: CGFloat = SuzzmeTheme.Radius.card,
                              tint: Color? = nil) -> some View {
        modifier(SuzzmeContentSurface(cornerRadius: cornerRadius, tint: tint))
    }
}

private struct SuzzmeContentSurface: ViewModifier {
    let cornerRadius: CGFloat
    var tint: Color? = nil

    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background(SuzzmeTheme.backgroundSecondary, in: shape)
            .overlay {
                if let tint {
                    shape.fill(tint.opacity(0.06)).allowsHitTesting(false)
                }
            }
            .overlay(shape.strokeBorder(
                contrast == .increased ? SuzzmeTheme.textSecondary : SuzzmeTheme.separator,
                lineWidth: contrast == .increased ? 2 : SuzzmeTheme.hairline
            ))
    }
}
