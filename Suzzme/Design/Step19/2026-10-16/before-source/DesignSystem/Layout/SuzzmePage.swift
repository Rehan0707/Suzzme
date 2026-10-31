import SwiftUI

/// One readable rhythm for native lists and forms, including secondary screens.
private struct SuzzmeNativeCollection: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .environment(\.defaultMinListRowHeight, SuzzmeTheme.Layout.touchTarget)
            .scrollContentBackground(.hidden)
            .tint(SuzzmeTheme.textPrimary)
            .frame(maxWidth: SuzzmeTheme.Layout.readingWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(SuzzmeTheme.pageBackground)
        #else
        content
            .environment(\.defaultMinListRowHeight, SuzzmeTheme.Layout.rowMinimum)
            .scrollContentBackground(.hidden)
            .tint(SuzzmeTheme.textPrimary)
            .background(SuzzmeTheme.pageBackground)
        #endif
    }
}

struct SuzzmePage<Content: View>: View {
    var contentWidth = SuzzmeTheme.Layout.readingWidth
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.extraLarge) {
                content
            }
            .padding(.horizontal, SuzzmeTheme.Layout.compactInset)
            .padding(.top, SuzzmeTheme.Spacing.large)
            .padding(.bottom, SuzzmeTheme.Spacing.hero)
            .frame(maxWidth: contentWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .background(SuzzmeTheme.pageBackground.ignoresSafeArea())
    }
}

extension View {
    func suzzmeSettingsForm() -> some View {
        formStyle(.grouped).modifier(SuzzmeNativeCollection())
    }

    /// Keep native list behavior while giving desktop content a readable measure.
    @ViewBuilder func suzzmeReadableList() -> some View {
        modifier(SuzzmeNativeCollection())
    }
}
