import AppKit
import SwiftUI

/// Isolated native rendering of production artwork/components, with labelled
/// visual fixtures. It never starts a microphone or simulates assistant events.
@main @MainActor struct MascotRender {
    static func main() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        precondition(NSImage(named: "SuzzmeMascot") != nil, "Production mascot asset must resolve")
        var speaking: [SuzzmeMascotColor: SuzzmeMascotFrames] = [:]
        for color in SuzzmeMascotColor.allCases {
            guard let frames = await SuzzmeMascotAnimationCache.shared.frames(named: color.animationName) else {
                preconditionFailure("Missing supplied speaking asset: \(color.animationName)")
            }
            precondition(frames.images.count == 16 && abs(frames.duration - 1.44) < 0.001)
            speaking[color] = frames
        }
        for dark in [false, true] {
            let gallery = VStack(alignment: .leading, spacing: 24) {
                Text("Suzzme · cloud companion").font(.title2.bold())
                Text("Native presentation fixtures · activity is labelled, not running")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 32) {
                    tile("Idle", state: .idle)
                    tile("Greeting", state: .idle, greeting: true)
                    tile("Listening", state: .listening)
                    tile("Thinking", state: .reasoning)
                }
                HStack(spacing: 32) {
                    tile("Speaking", state: .speaking)
                    tile("Success", state: .success)
                    tile("Sleeping", state: .idle, sleeping: true)
                    tile("Needs attention", state: .error)
                }
                Divider()
                HStack(alignment: .center, spacing: 24) {
                    ForEach([24, 44, 80, 128], id: \.self) { size in
                        VStack {
                            SuzzmeMascot(size: CGFloat(size), isAnimated: false)
                            Text("\(size) pt").font(.caption)
                        }
                    }
                    Spacer()
                    Text("Original blue artwork\nReduced Motion / Minimal stays still")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(32).frame(width: 800)
            .background(dark ? Color(white: 0.10) : .white)
            .foregroundStyle(dark ? .white : .black)
            .environment(\.colorScheme, dark ? .dark : .light)
            try save(gallery, to: output.appendingPathComponent(dark ? "mascot-dark.png" : "mascot-light.png"))
            let colors = VStack(spacing: 16) {
                Text("Supplied character colors · static frames").font(.headline)
                ForEach([Array(SuzzmeMascotColor.allCases.prefix(4)), Array(SuzzmeMascotColor.allCases.suffix(4))], id: \.self) { row in
                    HStack(spacing: 20) {
                        ForEach(row) { color in
                            VStack {
                                SuzzmeMascot(size: 128, isAnimated: false, characterColor: color)
                                Text(color.title).font(.caption)
                                if let frames = speaking[color] {
                                    SuzzmeSpeakingFrame(image: frames.images[4], maskAsset: color.assetName)
                                        .frame(width: 156, height: 156)
                                        .frame(width: 128, height: 128).clipped()
                                }
                            }
                        }
                    }
                }
            }.padding(24)
                .background(dark ? Color(white: 0.10) : .white)
                .foregroundStyle(dark ? .white : .black)
            try save(colors, to: output.appendingPathComponent(dark ? "supplied-colors-dark.png" : "supplied-colors-light.png"))
        }
        for width in [320, 390, 440] {
            let card = SuzzmeAssistantPresenceView(state: .listening, animation: .minimal, audioLevel: 0.4, onCancel: {})
                .padding(16).frame(width: CGFloat(width))
                .background(.white).environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .accessibility3)
            try save(card, to: output.appendingPathComponent("presence-\(width)-large-type.png"))
        }
        print("Mascot: original + eight colors resolved; eight GIFs decoded with 16 frames/1.44 seconds; 4 galleries and 3 accessibility layouts saved to \(output.path)")
    }

    static func tile(_ title: String, state: SuzzmeAssistantState, greeting: Bool = false, sleeping: Bool = false) -> some View {
        VStack(spacing: 8) {
            SuzzmeMascot(state: state, size: 144, isAnimated: false, isGreeting: greeting, isSleeping: sleeping)
            Text(title).font(.subheadline.weight(.medium))
        }.frame(width: 160)
    }

    static func save<V: View>(_ view: V, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}
