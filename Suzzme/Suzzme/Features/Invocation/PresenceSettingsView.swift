import SwiftUI

struct PresenceSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        SuzzmePage {
            SuzzmeSectionHeader(title: "Suzzme Presence")
            Text("Live preview").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            PresenceThemePreview(
                theme: environment.invocation.presenceTheme,
                animation: environment.invocation.presenceAnimation
            )
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Preview of \(environment.invocation.presenceTheme.accessibilityName)")

            SuzzmeCard {
                Picker("Presence theme", selection: Binding(
                    get: { environment.invocation.presenceTheme },
                    set: { environment.invocation.presenceTheme = $0 }
                )) {
                    ForEach(SuzzmePresenceTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .accessibilityHint("Changes Suzzme’s active intelligence signal")

                Picker("Presence animation", selection: Binding(
                    get: { environment.invocation.presenceAnimation },
                    set: { environment.invocation.presenceAnimation = $0 }
                )) {
                    ForEach(SuzzmePresenceAnimation.allCases) { animation in
                        Text(animation.title).tag(animation)
                    }
                }
                Text("Reduce Motion always replaces animated effects with calm state changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Suzzme Presence")
    }
}

struct PresenceThemePreview: View {
    let theme: SuzzmePresenceTheme
    let animation: SuzzmePresenceAnimation
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated = false

    var body: some View {
        let colors = theme.colors(for: colorScheme)
        ZStack {
            RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.largeSurface, style: .continuous)
                .fill(SuzzmeTheme.surfaceElevated)
            if !reduceMotion {
                Capsule()
                    .fill(LinearGradient(colors: [colors.primary, colors.secondary, colors.highlight], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 180, height: 4)
                    .blur(radius: animated ? 5 : 2)
                    .opacity(0.85)
                    .scaleEffect(x: animated ? 1.1 : 0.92)
            }
            VStack(spacing: 8) {
                SuzzmeFace(state: .listening, color: colors.face, lineWidth: 4, animation: animation)
                    .frame(width: 52, height: 52)
                Text("Listening…").font(.subheadline.weight(.medium)).foregroundStyle(SuzzmeTheme.textPrimary)
            }
        }
        .frame(height: 150)
        .overlay(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.largeSurface, style: .continuous).stroke(colors.primary.opacity(0.5), lineWidth: 1))
        .task(id: "\(theme.rawValue)-\(animation.rawValue)-\(reduceMotion)") {
            animated = false
            guard !reduceMotion, animation.duration > 0 else { return }
            withAnimation(.easeInOut(duration: animation.duration).repeatForever(autoreverses: true)) { animated = true }
        }
    }
}
