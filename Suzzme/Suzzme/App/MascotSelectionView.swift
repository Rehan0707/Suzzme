import SwiftUI

/// First-run, post-authentication character setup. The selected companion is
/// centered while the other colors move around it; no microphone is started.
struct MascotSelectionView: View {
    let onContinue: (SuzzmeMascotColor) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selection: SuzzmeMascotColor

    init(onContinue: @escaping (SuzzmeMascotColor) -> Void) {
        self.onContinue = onContinue
        _selection = State(initialValue: SuzzmeMascotColor(rawValue:
            UserDefaults.standard.string(forKey: SuzzmeMascotColor.defaultsKey) ?? "blue") ?? .blue)
    }

    var body: some View {
        ZStack {
            SuzzmeTheme.backgroundPrimary.ignoresSafeArea()
            RadialGradient(colors: [selection.surfaceTint, .clear], center: .top, startRadius: 20, endRadius: 520)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: SuzzmeTheme.Spacing.large) {
                    header
                    SuzzmeMascotColorOrbit(selection: $selection)
                    footer
                }
                .padding(.horizontal, SuzzmeTheme.Layout.compactInset)
                .padding(.top, SuzzmeTheme.Spacing.large)
                .padding(.bottom, SuzzmeTheme.Spacing.extraLarge)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .tint(selection.accent)
        .animation(reduceMotion ? nil : .smooth(duration: SuzzmeTheme.Motion.calm, extraBounce: 0), value: selection)
    }

    private var header: some View {
        VStack(spacing: SuzzmeTheme.Spacing.small) {
            SuzzmeMark()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            Text("Choose your Suzzme")
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Pick a companion from the circle. Its color will shape the app around you.")
                .font(.body)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
        }
        .padding(.bottom, SuzzmeTheme.Spacing.xs)
    }

    private var footer: some View {
        VStack(spacing: SuzzmeTheme.Spacing.xs) {
            Button {
                onContinue(selection)
            } label: {
                Text("Use \(selection.title)")
                    .frame(maxWidth: .infinity, minHeight: SuzzmeTheme.Layout.touchTarget)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("suzzme-mascot-color-continue")

            Text("You can change your companion’s color later in Presence settings.")
                .font(.footnote)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, SuzzmeTheme.Spacing.xs)
    }
}

/// Shared first-run and Settings selector. A selection rotates the ring while
/// the chosen character becomes the stable, larger focus in the center.
struct SuzzmeMascotColorOrbit: View {
    @Binding var selection: SuzzmeMascotColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: SuzzmeTheme.Spacing.xs) {
            GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let radius = diameter * 0.39
            let satelliteSize = min(72, diameter * 0.16)
            let centerSize = min(dynamicTypeSize.isAccessibilitySize ? 150 : 180, diameter * 0.42)
            let colors = SuzzmeMascotColor.allCases
            let selectedIndex = colors.firstIndex(of: selection) ?? 0

            ZStack {
                Circle()
                    .fill(selection.surfaceTint)
                    .frame(width: diameter * 0.63, height: diameter * 0.63)
                    .blur(radius: SuzzmeTheme.Spacing.hero)
                    .accessibilityHidden(true)

                ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                    let slot = (index - selectedIndex + colors.count) % colors.count
                    let angle = Double(slot) * 2 * Double.pi / Double(colors.count) - Double.pi / 2
                    Button {
                        selection = color
                    } label: {
                        SuzzmeMascot(state: .idle, size: satelliteSize,
                            isAnimated: false, characterColor: color)
                            .accessibilityHidden(true)
                            .frame(minWidth: SuzzmeTheme.Layout.touchTarget,
                                   minHeight: SuzzmeTheme.Layout.touchTarget)
                            .padding(4)
                            .background {
                                if selection == color {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .overlay(Circle().strokeBorder(color.accent.opacity(0.7), lineWidth: 1.5))
                                }
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: cos(angle) * radius, y: sin(angle) * radius)
                    .zIndex(selection == color ? 1 : 0)
                    .accessibilityLabel("Select \(color.title) mascot")
                    .accessibilityValue(selection == color ? "Selected" : "")
                    .accessibilityAddTraits(selection == color ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("suzzme-mascot-color-\(color.rawValue)")
                }

                VStack(spacing: SuzzmeTheme.Spacing.xs) {
                    SuzzmeMascot(state: .speaking, size: centerSize,
                        isAnimated: !reduceMotion, characterColor: selection)
                        .id(selection)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
                        .accessibilityHidden(true)
                    Text(selection.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(selection.accent)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(selection.title) mascot preview")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .smooth(duration: SuzzmeTheme.Motion.calm, extraBounce: 0), value: selection)
            }
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 430 : 390)

            Text(selection == .blue ? "Suzzme’s original color" : "Your companion, your color")
                .font(.subheadline)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview("Choose your Suzzme") {
    MascotSelectionView(onContinue: { _ in })
}
