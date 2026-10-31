import AppKit
import SwiftUI
@main @MainActor struct FinalUIPresenceRender {
    static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        if CommandLine.arguments.count > 2,
           let color = SuzzmeMascotColor(rawValue: CommandLine.arguments[2]) {
            SuzzmeMascotAppearance.shared.select(color)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for state in SuzzmeAssistantState.allCases {
            for mode in ["Light", "Dark", "LargeType"] {
                let dark = mode != "Light"
                let review: SuzzmePresenceReview? = state == .awaitingConfirmation ? .init(id: UUID(), title: "Delete ‘Submit project report’ from Reminders?", confirmationLabel: "Delete Reminder", isDestructive: true) : nil
                let response: String? = switch state {
                case .speaking, .success: "Your next class is at 10:30.\n\nBring your design notes. You have two unfinished reminders to leave room for afterward."
                case .error: "I couldn’t access Reminders. You can review access in Sources and try again."
                default: nil
                }
                let size = MacAssistantSurfaceMetrics.size(state: state, signal: .none, notchWidth: 180, review: review, response: response, notchHeight: 32, contextLabels: state == .gatheringContext ? ["Xcode", "Screen"] : [])
                let content = VStack(spacing: 0) {
                    Text("Development simulation · physical alignment pending").font(.caption).foregroundStyle(.secondary).padding(.bottom, 24)
                    ZStack(alignment: .top) {
                        UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                            .fill(.black)
                            .frame(width: 180, height: 32)
                        MacAssistantNotchSurface(state: state, theme: .suzzmePurple, animation: .minimal, signal: .none, hasNotch: true, notchWidth: 180, notchHeight: 32, review: review, response: response, audioLevel: state == .listening ? 0.55 : 0, contextLabels: state == .gatheringContext ? ["Xcode", "Screen"] : [], onConfirmation: { _ in }, onCancel: {}, onInvoke: {})
                            .frame(width: size.width, height: size.height)
                    }
                    .frame(height: size.height, alignment: .top)
                    Spacer()
                }.padding(.top, 28).frame(width: 540, height: 600).background(dark ? Color(white: 0.12) : Color.white).environment(\.colorScheme, dark ? .dark : .light).dynamicTypeSize(mode == "LargeType" ? .accessibility5 : .large)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                if let image = renderer.nsImage, let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: directory.appendingPathComponent("\(mode)-\(state.rawValue).png"))
                }
            }
        }
        for mode in ["Light", "Dark"] {
            let size = MacAssistantSurfaceMetrics.size(state: .idle, signal: .none,
                notchWidth: 180, review: nil, response: nil, notchHeight: 32, isHovered: true)
            let content = VStack(spacing: 0) {
                Text("Development simulation · physical alignment pending")
                    .font(.caption).foregroundStyle(.secondary).padding(.bottom, 24)
                MacAssistantNotchSurface(state: .idle, theme: .suzzmePurple,
                    animation: .minimal, signal: .none, hasNotch: true,
                    notchWidth: 180, notchHeight: 32, isHovered: true,
                    onCancel: {}, onInvoke: {}, onPushToTalkPress: {}, onPushToTalkRelease: {})
                    .frame(width: size.width, height: size.height)
                Spacer()
            }
            .padding(.top, 28)
            .frame(width: 540, height: 600)
            .background(mode == "Light" ? Color.white : Color(white: 0.12))
            .environment(\.colorScheme, mode == "Light" ? .light : .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            if let image = renderer.nsImage, let data = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: data),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: directory.appendingPathComponent("\(mode)-hover.png"))
            }
        }
        for hasNotch in [true, false] {
            for alreadyAllowed in [false, true] {
                for mode in ["Light", "Dark", "LargeType"] {
                    let request = MacGitHubConnectionRequest(service: .github, repository: "long-owner-name/long-repository-name", id: UUID(), alreadyAllowed: alreadyAllowed)
                    let size = MacAssistantSurfaceMetrics.size(state: .idle, signal: .none, notchWidth: 180, review: nil, response: nil, connectionRequest: request, notchHeight: hasNotch ? 32 : 0)
                    let content = MacAssistantNotchSurface(state: .idle, theme: .suzzmePurple, animation: .minimal, signal: .none, hasNotch: hasNotch, notchWidth: 180, notchHeight: hasNotch ? 32 : 0, connectionRequest: request, onConnectionDecision: { _ in }, onCancel: {}, onInvoke: {})
                        .frame(width: size.width, height: size.height)
                        .padding(24)
                        .background(mode == "Light" ? Color.white : Color(white: 0.12))
                        .environment(\.colorScheme, mode == "Light" ? .light : .dark)
                        .dynamicTypeSize(mode == "LargeType" ? .accessibility5 : .large)
                    let renderer = ImageRenderer(content: content)
                    renderer.scale = 2
                    if let image = renderer.nsImage, let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
                        try png.write(to: directory.appendingPathComponent("GitHub-\(hasNotch ? "Notch" : "Fallback")-\(alreadyAllowed ? "Allowed" : "Request")-\(mode).png"))
                    }
                }
            }
        }
    }
}
