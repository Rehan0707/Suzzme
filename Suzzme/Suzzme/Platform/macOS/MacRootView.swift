#if os(macOS)
import SwiftUI

struct MacRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppEnvironment.self) private var environment
    @State private var showsAssistant = false
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            ScrollView {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.large) {
                    HStack(spacing: SuzzmeTheme.Spacing.small) {
                        SuzzmeFace(color: SuzzmeTheme.textPrimary, lineWidth: 2.8)
                            .frame(width: SuzzmeTheme.Spacing.extraLarge, height: SuzzmeTheme.Spacing.extraLarge)
                        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                            Text("Suzzme").font(.headline)
                            Text("Your personal companion")
                                .font(.caption)
                                .foregroundStyle(SuzzmeTheme.textSecondary)
                        }
                    }
                    .padding(.vertical, SuzzmeTheme.Spacing.xs)
                    .padding(.horizontal, SuzzmeTheme.Spacing.small)
                    .accessibilityElement(children: .combine)

                    sidebarSection("Your day") {
                        row(.home)
                        row(.today)
                        row(.briefing)
                    }
                    sidebarSection("Your information") {
                        row(.memory)
                        row(.sources)
                        row(.history)
                    }
                    row(.settings)
                }
                .padding(.horizontal, SuzzmeTheme.Spacing.xs)
                .padding(.vertical, SuzzmeTheme.Spacing.medium)
            }
            .background(.regularMaterial)
            .navigationTitle("Suzzme")
            .navigationSplitViewColumnWidth(min: SuzzmeTheme.Layout.sidebarMin, ideal: SuzzmeTheme.Layout.sidebarIdeal, max: SuzzmeTheme.Layout.sidebarMax)
        } detail: {
            MacRootDetail(selection: router.selection, showsAssistant: $showsAssistant)
                .id(router.selection)
        }
        .navigationSplitViewStyle(.balanced)
        // NavigationSplitView can retain a pushed detail even after the
        // sidebar selection changes. Give each root destination its own
        // navigation lifetime so the visible page matches the selected row.
        .id(router.selection)
        .tint(SuzzmeTheme.controlAccent)
        .frame(minWidth: SuzzmeTheme.Layout.windowMinWidth, minHeight: SuzzmeTheme.Layout.windowMinHeight)
        .background(SuzzmeTheme.pageBackground)
        .background(MacWorkspaceEscapeBridge {
            guard !showsAssistant, let owner = environment.currentInteractionID else { return false }
            Task { await environment.dismissInteraction(owner) }
            return true
        })
        .focusedSceneValue(\.assistantPresentation, $showsAssistant)
        .sheet(isPresented: $showsAssistant) {
            AskSuzzmeView(focusInput: true)
                .frame(minWidth: 440, idealWidth: SuzzmeTheme.Layout.readingWidth, minHeight: 560)
        }
    }

    private func row(_ destination: AppDestination) -> some View {
        MacGlassSidebarRow(
            title: destination.title,
            symbol: destination.symbol,
            isSelected: router.selection == destination,
            identifier: "suzzme-navigation-\(destination.rawValue)"
        ) { router.selection = destination }
    }

    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .padding(.horizontal, SuzzmeTheme.Spacing.small)
                .padding(.bottom, SuzzmeTheme.Spacing.xxs)
            content()
        }
    }
}

private struct MacRootDetail: View {
    let selection: AppDestination
    @Binding var showsAssistant: Bool

    var body: some View {
        Group {
            if selection == .settings {
                // Separate stacks discard a pushed Settings page when the
                // sidebar switches to another destination.
                NavigationStack {
                    SettingsView(usesDesktopSidebar: false)
                        .modifier(MacAskToolbar(showsAssistant: $showsAssistant))
                }
            } else {
                NavigationStack {
                    DestinationView(destination: selection)
                        .modifier(MacAskToolbar(showsAssistant: $showsAssistant))
                }
            }
        }
        .tint(SuzzmeTheme.controlAccent)
    }
}

private struct MacAskToolbar: ViewModifier {
    @Binding var showsAssistant: Bool

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showsAssistant = true } label: { Label("Ask Suzzme", systemImage: "text.bubble") }
                    .labelStyle(.titleAndIcon)
                    .help("Ask Suzzme (⌘K)")
                    .accessibilityIdentifier("suzzme-ask-open")
            }
        }
    }
}

/// Native sidebar material stays quiet; only the current destination gets a
/// restrained glass highlight in the selected companion color.
struct MacGlassSidebarRow: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let identifier: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SuzzmeTheme.Spacing.small) {
                Image(systemName: symbol)
                    .frame(width: SuzzmeTheme.Layout.symbolColumn)
                    .foregroundStyle(isSelected ? SuzzmeTheme.textPrimary : SuzzmeTheme.textSecondary)
                Text(title)
                    .foregroundStyle(SuzzmeTheme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SuzzmeTheme.Spacing.small)
            .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.control, style: .continuous)
                        .fill(SuzzmeTheme.controlFill)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.control, style: .continuous)
                        .fill(SuzzmeTheme.controlFill)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowBackground(Color.clear)
        .onHover { isHovered = $0 }
        .accessibilityIdentifier(identifier)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
#endif
