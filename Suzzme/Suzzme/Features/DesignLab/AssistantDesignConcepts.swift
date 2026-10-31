#if DEBUG
import SwiftUI

enum AssistantDesignConcept: String, CaseIterable, Identifiable {
    case minimal, ambient, editorial, floating, focus, workspace, voice, context, compact, signature
    case quietGlow, editorialContext, floatingVoice, workspaceFocus, signatureCompact
    var id: String { rawValue }
    var title: String {
        switch self {
        case .minimal: "Suzzme Minimal"
        case .ambient: "Suzzme Ambient"
        case .editorial: "Suzzme Editorial"
        case .floating: "Suzzme Floating"
        case .focus: "Suzzme Focus"
        case .workspace: "Suzzme Workspace"
        case .voice: "Suzzme Voice"
        case .context: "Suzzme Context"
        case .compact: "Suzzme Compact"
        case .signature: "Suzzme Signature"
        case .quietGlow: "Quiet Glow"
        case .editorialContext: "Editorial Context"
        case .floatingVoice: "Floating Voice"
        case .workspaceFocus: "Workspace Focus"
        case .signatureCompact: "Signature Compact"
        }
    }
    var subtitle: String {
        switch self {
        case .minimal: "Clarity, calm, and native restraint"
        case .ambient: "Soft intelligence light with quiet depth"
        case .editorial: "Reading-first typography and generous rhythm"
        case .floating: "A lightweight companion that stays out of the way"
        case .focus: "One conversation, no visual noise"
        case .workspace: "Mac productivity with context at hand"
        case .voice: "Conversation led by listening and speech"
        case .context: "Authorized personal context made visible"
        case .compact: "Useful in a narrow or short window"
        case .signature: "The Face, purple presence, and composed detail"
        case .quietGlow: "Minimal structure with ambient intelligence"
        case .editorialContext: "Reading comfort plus sourced context"
        case .floatingVoice: "A floating conversation with voice energy"
        case .workspaceFocus: "Productive context around a focused thread"
        case .signatureCompact: "Suzzme identity distilled for small windows"
        }
    }
    var layout: AssistantConceptLayout {
        switch self {
        case .workspace, .workspaceFocus: .workspace
        case .voice, .floatingVoice: .voice
        case .context, .editorialContext: .context
        case .compact, .signatureCompact: .compact
        default: .conversation
        }
    }
    var centered: Bool { [.ambient, .focus, .voice, .floatingVoice, .workspaceFocus].contains(self) }
    var editorial: Bool { [.editorial, .editorialContext].contains(self) }
    var floating: Bool { [.floating, .quietGlow, .floatingVoice].contains(self) }
    var ambient: Bool { [.ambient, .quietGlow, .floatingVoice, .signature].contains(self) }
    var signature: Bool { [.signature, .workspaceFocus, .signatureCompact].contains(self) }
}

enum AssistantConceptLayout { case conversation, workspace, voice, context, compact }

struct AssistantDesignConceptView: View {
    let concept: AssistantDesignConcept
    let previewState: AssistantPreviewState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ZStack {
            SuzzmeTheme.backgroundPrimary
            if concept.ambient {
                Circle().fill(SuzzmeTheme.intelligencePrimary.opacity(0.12)).frame(width: 380, height: 380).blur(radius: 100).offset(x: 150, y: -180).accessibilityHidden(true)
            }
            switch concept.layout {
            case .conversation: conversation
            case .workspace: workspace
            case .voice: voice
            case .context: context
            case .compact: compact
            }
        }
        .tint(SuzzmeTheme.intelligencePrimary)
    }

    private var conversation: some View {
        shell {
            header
            transcript
            AssistantPreviewComposer(floating: concept.floating, compact: false)
        }
    }

    private var workspace: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                if proxy.size.width > 720 { AssistantPreviewSidebar().frame(width: min(240, proxy.size.width * 0.28)); Divider() }
                shell(maxWidth: SuzzmeTheme.Layout.readingWidth) { header; transcript; AssistantPreviewComposer(floating: false, compact: false) }
            }
        }
    }

    private var voice: some View {
        shell(maxWidth: SuzzmeTheme.Layout.companionWidth) {
            ZStack {
                Circle().fill(SuzzmeTheme.intelligenceSurface).frame(width: 168, height: 168)
                Circle().stroke(SuzzmeTheme.intelligencePrimary.opacity(0.22), lineWidth: 9).frame(width: 138, height: 138)
                SuzzmeFace(state: previewState.assistantState, audioLevel: previewState == .listening ? 0.72 : 0).frame(width: 82, height: 82)
            }.frame(maxWidth: .infinity)
            Text(previewState.status).font(.title2.weight(.semibold)).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            AssistantPreviewVoiceMeter(active: [.listening, .transcribing, .speaking].contains(previewState))
            transcript
            AssistantPreviewComposer(floating: concept.floating, compact: false)
        }
    }

    private var context: some View {
        shell(maxWidth: SuzzmeTheme.Layout.workspaceWidth) {
            header
            AssistantPreviewContextStrip()
            transcript
            AssistantPreviewComposer(floating: false, compact: false)
        }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            header
            transcript
            AssistantPreviewComposer(floating: false, compact: true)
        }
        .padding(SuzzmeTheme.Spacing.medium)
        .frame(maxWidth: 480, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        VStack(alignment: concept.centered ? .center : .leading, spacing: SuzzmeTheme.Spacing.xs) {
            if concept.signature {
                SuzzmeFace(state: previewState.assistantState, color: .white, lineWidth: 5)
                    .padding(SuzzmeTheme.Spacing.large).frame(width: 112, height: 112)
                    .background(SuzzmeTheme.accentGradient, in: RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.hero))
            } else {
                SuzzmeFace(state: previewState.assistantState).frame(width: 62, height: 62)
            }
            Text(concept.title)
                .font(concept.editorial ? .largeTitle.weight(.medium) : .title.weight(.semibold))
                .tracking(concept.editorial ? -0.8 : 0)
                .accessibilityAddTraits(.isHeader)
            Text(concept.subtitle).font(.subheadline).foregroundStyle(.secondary)
            SuzzmeStateLabel(title: previewState.status, symbol: previewState.assistantState == .error ? "exclamationmark.circle" : "lock.shield", tone: previewState.assistantState == .error ? SuzzmeTheme.warning : SuzzmeTheme.intelligencePrimary)
        }
        .frame(maxWidth: .infinity, alignment: concept.centered ? .center : .leading)
        .multilineTextAlignment(concept.centered ? .center : .leading)
    }

    private var transcript: some View {
        AssistantPreviewTranscript(state: previewState, editorial: concept.editorial, material: concept.ambient || concept.signature)
    }

    private func shell<Content: View>(maxWidth: CGFloat = SuzzmeTheme.Layout.readingWidth, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? SuzzmeTheme.Spacing.extraLarge : SuzzmeTheme.Spacing.large) { content() }
                .padding(SuzzmeTheme.Layout.pageInset).frame(maxWidth: maxWidth, alignment: .leading).frame(maxWidth: .infinity)
                .background {
                    if concept.floating { RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.largeSurface).fill(.regularMaterial).shadow(color: .black.opacity(0.08), radius: 24, y: 10) }
                }
                .padding(concept.floating ? SuzzmeTheme.Spacing.large : 0)
        }
    }
}

private struct AssistantPreviewTranscript: View {
    let state: AssistantPreviewState
    let editorial: Bool
    let material: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.large) {
            if let notice = state.notice { noticeView(notice) }
            if state.messages.isEmpty, state.notice == nil {
                SuzzmeEmptyState(symbol: "bubble.left.and.bubble.right", title: "Start a conversation", message: "Ask a question, think through an idea, or use authorized context from your day.")
            }
            ForEach(state.messages) { message in
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                    Text(message.role == .user ? "You" : "Suzzme").font(.caption.weight(.semibold)).foregroundStyle(message.role == .assistant ? SuzzmeTheme.intelligencePrimary : .secondary)
                    Text(message.text).font(editorial && message.role == .assistant ? .title3 : .body).lineSpacing(SuzzmeTheme.Spacing.xxs).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if message.role == .assistant { Label("Generated on this device", systemImage: "apple.intelligence").font(.caption2).foregroundStyle(.secondary) }
                }
                .padding(message.role == .assistant && material ? SuzzmeTheme.Spacing.medium : 0)
                .background(message.role == .assistant && material ? SuzzmeTheme.intelligenceSurface : .clear, in: RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.card))
                .accessibilityElement(children: .combine)
            }
            if [.listening, .transcribing, .thinking].contains(state) { HStack { ProgressView().controlSize(.small); Text(state.status).font(.subheadline).foregroundStyle(.secondary) } }
        }
    }
    private func noticeView(_ notice: AssistantPreviewNotice) -> some View {
        HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.medium) {
            Image(systemName: notice.symbol).font(.title3).foregroundStyle(notice.warning ? SuzzmeTheme.warning : SuzzmeTheme.textSecondary)
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                Text(notice.title).font(.headline)
                Text(notice.detail).font(.subheadline).foregroundStyle(.secondary)
                Button("Review settings") { }
                    .buttonStyle(.plain)
                    .foregroundStyle(SuzzmeTheme.intelligencePrimary)
            }
        }.padding(SuzzmeTheme.Spacing.medium).background(SuzzmeTheme.controlFill, in: RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.card))
    }
}

private struct AssistantPreviewComposer: View {
    let floating: Bool
    let compact: Bool
    var body: some View {
        HStack(spacing: SuzzmeTheme.Spacing.small) {
            Button { } label: { Image(systemName: "mic") }.buttonStyle(.plain).frame(width: SuzzmeTheme.Layout.touchTarget, height: SuzzmeTheme.Layout.touchTarget).accessibilityLabel("Preview voice control")
            Text("Ask Suzzme…").font(compact ? .subheadline : .body).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button { } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderedProminent).buttonBorderShape(.circle).accessibilityLabel("Preview send control")
        }
        .padding(.horizontal, SuzzmeTheme.Spacing.small).frame(minHeight: SuzzmeTheme.Layout.touchTarget)
        .background(floating ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(SuzzmeTheme.controlFill), in: RoundedRectangle(cornerRadius: floating ? SuzzmeTheme.Radius.hero : SuzzmeTheme.Radius.control))
    }
}

private struct AssistantPreviewVoiceMeter: View {
    let active: Bool
    var body: some View {
        HStack(spacing: SuzzmeTheme.Spacing.xxs) { ForEach(0..<9, id: \.self) { index in Capsule().fill(active ? SuzzmeTheme.intelligencePrimary : SuzzmeTheme.separator).frame(width: 4, height: active ? CGFloat(10 + index % 4 * 7) : 8) } }
            .frame(maxWidth: .infinity, minHeight: 42).accessibilityLabel(active ? "Simulated voice activity for visual design" : "Voice activity inactive")
    }
}

private struct AssistantPreviewContextStrip: View {
    var body: some View { ViewThatFits(in: .horizontal) { HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.small) { cards }; VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) { cards } } }
    @ViewBuilder private var cards: some View { ForEach(AssistantPreviewContext.samples) { item in SuzzmeCard { Label(item.title, systemImage: item.symbol).font(.caption.weight(.semibold)).foregroundStyle(SuzzmeTheme.intelligencePrimary); Text(item.detail).font(.subheadline) } } }
}

private struct AssistantPreviewSidebar: View {
    var body: some View { List { Section("Conversation") { Label("New conversation", systemImage: "square.and.pencil"); Label("Today", systemImage: "clock") }; Section("Context") { Label("Calendar", systemImage: "calendar"); Label("Reminders", systemImage: "checklist"); Label("Memory", systemImage: "brain") } }.listStyle(.sidebar).accessibilityLabel("Preview sidebar") }
}

#Preview("01 · Suzzme Minimal") { AssistantDesignConceptView(concept: .minimal, previewState: .success) }
#Preview("02 · Suzzme Ambient · Dark") { AssistantDesignConceptView(concept: .ambient, previewState: .thinking).preferredColorScheme(.dark) }
#Preview("03 · Suzzme Editorial") { AssistantDesignConceptView(concept: .editorial, previewState: .longResponse) }
#Preview("04 · Suzzme Floating · Dark") { AssistantDesignConceptView(concept: .floating, previewState: .shortMessage).preferredColorScheme(.dark) }
#Preview("05 · Suzzme Focus") { AssistantDesignConceptView(concept: .focus, previewState: .thinking) }
#Preview("06 · Suzzme Workspace") { AssistantDesignConceptView(concept: .workspace, previewState: .longConversation) }
#Preview("07 · Suzzme Voice · Dark") { AssistantDesignConceptView(concept: .voice, previewState: .listening).preferredColorScheme(.dark) }
#Preview("08 · Suzzme Context") { AssistantDesignConceptView(concept: .context, previewState: .success) }
#Preview("09 · Suzzme Compact") { AssistantDesignConceptView(concept: .compact, previewState: .permissionDenied) }
#Preview("10 · Suzzme Signature · Dark") { AssistantDesignConceptView(concept: .signature, previewState: .speaking).preferredColorScheme(.dark) }
#Preview("11 · Quiet Glow") { AssistantDesignConceptView(concept: .quietGlow, previewState: .success) }
#Preview("12 · Editorial Context · Dark") { AssistantDesignConceptView(concept: .editorialContext, previewState: .longResponse).preferredColorScheme(.dark) }
#Preview("13 · Floating Voice") { AssistantDesignConceptView(concept: .floatingVoice, previewState: .listening) }
#Preview("14 · Workspace Focus · Dark") { AssistantDesignConceptView(concept: .workspaceFocus, previewState: .longConversation).preferredColorScheme(.dark) }
#Preview("15 · Signature Compact") { AssistantDesignConceptView(concept: .signatureCompact, previewState: .modelUnavailable) }
#Preview("Large Text Accessibility") { AssistantDesignConceptView(concept: .minimal, previewState: .largeText).environment(\.dynamicTypeSize, .accessibility3) }
#endif
