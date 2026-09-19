import SwiftUI

struct SuzzmeMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(SuzzmeTheme.wash)
            SuzzmeFace(color: SuzzmeTheme.accent, lineWidth: 2.8).padding(8)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Suzzme")
    }
}
