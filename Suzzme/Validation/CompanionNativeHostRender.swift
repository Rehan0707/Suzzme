import AppKit
import SwiftUI

/// Exact shared production views on a macOS host. This inspects appearance;
/// it does not claim iPhone font metrics or system Live Activity delivery.
@main @MainActor struct CompanionNativeHostRender {
    static func main() throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, scheme) in [("Light", ColorScheme.light), ("Dark", .dark)] {
            let content = VStack(alignment: .leading, spacing: 20) {
                Text("Suzzme Companion · Native SwiftUI").font(.title2.bold())
                Text("Shared production views · macOS host render · Sample states")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach([SuzzmeLiveActivityPhase.checking, .understanding, .speaking, .summaryReady], id: \.self) { phase in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(phase.title).font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .top, spacing: 24) {
                            SuzzmeCompanionActivityCard(phase: phase, motionEnabled: false)
                                .frame(width: 374)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 26))
                            SuzzmeCompanionSmallView(entry: entry(phase))
                                .padding(16).frame(width: 170, height: 170)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 22))
                        }
                    }
                }
            }
            .padding(28).frame(width: 650, alignment: .leading)
            .background(scheme == .dark ? Color(white: 0.06) : Color(white: 0.94))
            .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: output.appendingPathComponent("Companion-Host-\(name).png"))
        }
    }

    private static func entry(_ phase: SuzzmeLiveActivityPhase) -> SuzzmeCompanionEntry {
        let now = Date.now
        return .init(date: now, snapshot: .init(phase: phase.isTerminal ? nil : phase,
            updatedAt: now, summaryGeneratedAt: phase.isTerminal ? now : nil,
            summaryExpiresAt: phase.isTerminal ? now.addingTimeInterval(7200) : nil))
    }
}
