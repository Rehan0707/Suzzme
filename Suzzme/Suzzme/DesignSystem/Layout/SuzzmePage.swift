import SwiftUI

struct SuzzmePage<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) { content }
                .padding(SuzzmeTheme.spacing)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background(SuzzmeTheme.background)
    }
}
