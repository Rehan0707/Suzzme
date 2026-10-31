#if DEBUG
import SwiftUI

struct ApprovedAssistantCompositionView: View {
    let previewState: AssistantPreviewState

    var body: some View {
        GeometryReader { proxy in
            AssistantDesignConceptView(
                concept: concept(for: proxy.size.width),
                previewState: previewState
            )
        }
    }

    private func concept(for width: CGFloat) -> AssistantDesignConcept {
        if [.listening, .transcribing, .speaking].contains(previewState), width < 760 {
            return .floatingVoice
        }
        if width >= 820 {
            return .workspaceFocus
        }
        if width < 520 {
            return .signatureCompact
        }
        if [.thinking, .success].contains(previewState) {
            return .signature
        }
        return .minimal
    }
}

#if os(macOS)
private enum GalleryAppearance: String, CaseIterable, Identifiable {
    case light, dark

    var id: String { rawValue }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

struct ApprovedDesignGalleryView: View {
    @State private var previewState = AssistantPreviewState.success
    @State private var appearance = GalleryAppearance.light
    @State private var simulatedWidth = 920.0

    var body: some View {
        HSplitView {
            ScrollView([.horizontal, .vertical]) {
                ApprovedAssistantCompositionView(previewState: previewState)
                    .frame(width: simulatedWidth, height: 680)
                    .clipShape(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.largeSurface))
                    .overlay {
                        RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.largeSurface)
                            .strokeBorder(.separator.opacity(0.45))
                    }
                    .padding(SuzzmeTheme.Spacing.large)
            }
            .background(SuzzmeTheme.backgroundSecondary)

            Form {
                Section("Approved direction") {
                    Text("Minimal Foundation + Signature Intelligence + Adaptive Workspace")
                        .font(.headline)
                    Text("This gallery uses preview fixtures only. It does not activate the microphone or invoke AI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Validation") {
                    Picker("State", selection: $previewState) {
                        ForEach(AssistantPreviewState.allCases) { state in
                            Text(state.title).tag(state)
                        }
                    }
                    Picker("Appearance", selection: $appearance) {
                        ForEach(GalleryAppearance.allCases) { value in
                            Text(value.rawValue.capitalized).tag(value)
                        }
                    }
                    Slider(value: $simulatedWidth, in: 420...1100, step: 20) {
                        Text("Content width")
                    }
                    Text("Width: \(Int(simulatedWidth)) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Section("Motion") {
                    NavigationLink("Open Presence Animation Playground") {
                        PresenceAnimationPlayground()
                    }
                    Text("The approved motion preset is the playground default.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 380)
            .padding(.vertical, SuzzmeTheme.Spacing.medium)
        }
        .preferredColorScheme(appearance.colorScheme)
        .navigationTitle("Approved Design Gallery")
        .frame(minWidth: 900, minHeight: 700)
    }
}

struct ApprovedDesignGalleryCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Design") {
            Button("Open Approved Design Gallery") {
                openWindow(id: "approved-design-gallery")
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
        }
    }
}
#endif

#Preview("Approved · Wide · Light") {
    ApprovedAssistantCompositionView(previewState: .success)
        .frame(width: 980, height: 720)
        .preferredColorScheme(.light)
}

#Preview("Approved · Wide · Dark Error") {
    ApprovedAssistantCompositionView(previewState: .modelUnavailable)
        .frame(width: 980, height: 720)
        .preferredColorScheme(.dark)
}

#Preview("Approved · Compact Voice") {
    ApprovedAssistantCompositionView(previewState: .listening)
        .frame(width: 430, height: 720)
        .preferredColorScheme(.dark)
}

#Preview("Approved · Large Text") {
    ApprovedAssistantCompositionView(previewState: .largeText)
        .frame(width: 620, height: 760)
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
