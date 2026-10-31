import SwiftUI

/// Shared with the Share extension, which bundles its own character asset.
struct SuzzmeMark: View {
    @AppStorage("suzzme.mascot.color") private var mascotColor = "blue"

    private var imageName: String {
        let allowed = ["blue", "pink", "red", "orange", "yellow", "green", "teal", "purple"]
        guard allowed.contains(mascotColor), mascotColor != "blue" else { return "SuzzmeMascot" }
        return "SuzzmeMascot\(mascotColor.capitalized)"
    }

    var body: some View {
        GeometryReader { geometry in
            Image(imageName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .scaleEffect(1.22)
                .offset(y: -min(geometry.size.width, geometry.size.height) * 0.022)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
        .accessibilityLabel("Suzzme")
    }
}
