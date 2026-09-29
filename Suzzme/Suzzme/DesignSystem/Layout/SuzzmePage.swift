import SwiftUI

struct SuzzmePage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.extraLarge) {
                content
            }
            .padding(.horizontal, SuzzmeTheme.Spacing.large)
            .padding(.top, SuzzmeTheme.Spacing.large)
            .padding(.bottom, 88)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(SuzzmeTheme.backgroundPrimary.ignoresSafeArea())
    }
}
