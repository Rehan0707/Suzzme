import AppKit
import SwiftUI
@main @MainActor struct FinalUIPresenceRender {
    static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for state in SuzzmeAssistantState.allCases where state != .idle {
            for dark in [false, true] {
                let review: SuzzmePresenceReview? = state == .awaitingConfirmation ? .init(id: UUID(), title: "Delete ‘Submit project report’ from Reminders?", confirmationLabel: "Delete Reminder", isDestructive: true) : nil
                let response = state == .speaking ? "Your project review is at 11 AM in Lab 2. Bring your design notes. You can interrupt with a question." : nil
                let size = MacAssistantSurfaceMetrics.size(state: state, signal: .none, notchWidth: 180, review: review, response: response)
                let content = VStack(spacing: 0) {
                    Text("Development simulation · physical alignment pending").font(.caption).foregroundStyle(.secondary).padding(.bottom, 24)
                    UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(.black).frame(width: 180, height: 28)
                    MacAssistantNotchSurface(state: state, theme: .suzzmePurple, animation: .minimal, signal: .none, hasNotch: true, notchWidth: 180, review: review, response: response, onConfirmation: { _ in }, onCancel: {}, onInvoke: {})
                        .frame(width: size.width, height: size.height)
                    Spacer()
                }.padding(.top, 28).frame(width: 540, height: 460).background(dark ? Color(white: 0.12) : Color.white).environment(\.colorScheme, dark ? .dark : .light)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                if let image = renderer.nsImage, let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
                    try png.write(to: directory.appendingPathComponent("\(dark ? "Dark" : "Light")-\(state.rawValue).png"))
                }
            }
        }
    }
}
