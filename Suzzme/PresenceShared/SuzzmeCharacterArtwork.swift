import SwiftUI

/// Static identity artwork shared with the system activity extension.
/// It uses the original character and cannot start or simulate assistant work.
struct SuzzmeCharacterArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            Image("SuzzmeMascot")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .scaleEffect(1.22)
                .offset(y: -min(geometry.size.width, geometry.size.height) * 0.022)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}
