import SwiftUI

/// Shared in-app presentation for the one Suzzme assistant state machine.
struct SuzzmeAssistantPresenceView: View {
    let state: SuzzmeAssistantState
    var showsCancel: Bool = true
    var onCancel: (() -> Void)?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var presentation: SuzzmeAssistantPresentation { .make(for: state) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(signalColor.opacity(reduceTransparency ? 0.18 : 0.28))
                SuzzmeFace(state: state, color: signalColor, lineWidth: 3.5).padding(10)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(presentation.systemStatus).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsCancel, isCancellable {
                Button("Cancel", action: { onCancel?() })
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityLabel("Cancel Suzzme")
                    .accessibilityHint("Stops listening and cancels the current request")
            }
        }
        .padding(12)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(signalColor.opacity(reduceTransparency ? 0.55 : 0.20), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.systemStatus)
        .accessibilityAddTraits(.isStatus)
    }

    private var isCancellable: Bool {
        switch state {
        case .listening, .transcribing, .understanding, .gatheringContext, .reasoning, .planning, .acting, .speaking: true
        case .idle, .awaitingConfirmation, .success, .error: false
        }
    }

    private var signalColor: Color {
        switch presentation.emphasis {
        case .error: .red
        case .success: .green
        case .ambient, .active, .confirmation: SuzzmeTheme.accent
        }
    }

    @ViewBuilder private var backgroundStyle: some View {
        if reduceTransparency { SuzzmeTheme.surface }
        else { Rectangle().fill(.regularMaterial) }
    }
}

struct SuzzmeAssistantPresenceOverlay: View {
    let state: SuzzmeAssistantState
    var onCancel: (() -> Void)?
    private var presentation: SuzzmeAssistantPresentation { .make(for: state) }

    var body: some View {
        if presentation.isVisible {
            SuzzmeAssistantPresenceView(state: state, onCancel: onCancel)
                .frame(maxWidth: 420)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .animation(.easeInOut(duration: 0.22), value: state)
                .accessibilityIdentifier("suzzme-assistant-presence")
        }
    }
}
