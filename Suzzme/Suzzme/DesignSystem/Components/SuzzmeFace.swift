import SwiftUI

/// Suzzme's three-stroke face: two calm upper chevrons and one lower smile.
/// The geometry is intentionally small and stable at every presentation size.
struct SuzzmeFace: View {
    var state: SuzzmeAssistantState = .idle
    var color: Color = SuzzmeTheme.accent
    var lineWidth: CGFloat = 4

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var activePhase = false

    var body: some View {
        SuzzmeFaceShape(state: state)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .scaleEffect(activePhase ? 1.025 : 1)
            .opacity(state == .idle ? 0.92 : 1)
            .task(id: "\(state.rawValue)-\(reduceMotion)-\(scenePhase == .active)") {
                activePhase = false
                guard state != .idle, !reduceMotion, scenePhase == .active else { return }
                withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                    activePhase = true
                }
            }
            .accessibilityHidden(true)
    }
}

struct SuzzmeFaceShape: Shape {
    var state: SuzzmeAssistantState = .idle

    func path(in rect: CGRect) -> Path {
        let lift: CGFloat = switch state {
        case .listening, .speaking: 0.018
        case .success: -0.012
        case .error: 0.012
        default: 0
        }
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        path.move(to: point(0.14, 0.43 + lift))
        path.addLine(to: point(0.29, 0.28 + lift))
        path.addLine(to: point(0.44, 0.43 + lift))
        path.move(to: point(0.56, 0.43 + lift))
        path.addLine(to: point(0.71, 0.28 + lift))
        path.addLine(to: point(0.86, 0.43 + lift))
        path.move(to: point(0.34, 0.62))
        path.addLine(to: point(0.50, 0.77))
        path.addLine(to: point(0.66, 0.62))
        return path
    }
}

#Preview("Suzzme Face") {
    VStack(spacing: 28) {
        ForEach(SuzzmeAssistantState.allCases, id: \.self) { state in
            SuzzmeFace(state: state)
                .frame(width: 64, height: 64)
                .accessibilityLabel(SuzzmeAssistantPresentation.make(for: state).systemStatus)
        }
    }
    .padding()
}
