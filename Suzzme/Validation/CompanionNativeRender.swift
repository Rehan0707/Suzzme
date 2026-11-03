import SwiftUI
import UIKit

/// Isolated native component review, compiled against the shipping view source.
/// Sample phases are not assistant work or evidence of ActivityKit delivery.
#if SUZZME_PRESENCE_RENDER_CLI
@main @MainActor struct CompanionNativeReviewCLI {
    static func main() { NativeCompanionExports.write() }
}
#else
@main struct CompanionNativeReview: App {
    var body: some Scene {
        WindowGroup {
            ScrollView([.horizontal, .vertical]) {
                CompanionReviewSheet(scheme: .dark, typeSize: .large)
            }
            .task { NativeCompanionExports.write() }
        }
    }
}
#endif

private struct CompanionReviewSheet: View {
    var scheme: ColorScheme
    var typeSize: DynamicTypeSize
    private let phases: [SuzzmeLiveActivityPhase] = [.checking, .understanding, .speaking, .summaryReady]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Suzzme Companion · Native SwiftUI").font(.title2.bold())
            Text("Production components · Sample states · Not a system delivery test")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(phases, id: \.self) { phase in
                VStack(alignment: .leading, spacing: 8) {
                    Text(phase.title).font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 24) {
                        SuzzmeCompanionActivityCard(phase: phase, motionEnabled: false)
                            .frame(width: 374)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 26))
                        SuzzmeCompanionSmallView(entry: entry(phase))
                            .padding(16).frame(width: 170, height: 170)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
                    }
                }
            }
        }
        .padding(28).frame(width: 650, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
        .environment(\.colorScheme, scheme)
        .dynamicTypeSize(typeSize)
    }

    private func entry(_ phase: SuzzmeLiveActivityPhase) -> SuzzmeCompanionEntry {
        let now = Date.now
        return .init(date: now, snapshot: .init(phase: phase.isTerminal ? nil : phase,
            updatedAt: now, summaryGeneratedAt: phase.isTerminal ? now : nil,
            summaryExpiresAt: phase.isTerminal ? now.addingTimeInterval(7200) : nil))
    }
}

@MainActor private enum NativeCompanionExports {
    static var written = false
    static func write() {
        guard !written else { return }; written = true
        let directory = CommandLine.arguments.count > 1
            ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true) : URL.documentsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var heights: [String: Double] = [:]
        for (name, scheme, size) in [("Light", ColorScheme.light, DynamicTypeSize.large), ("Dark", .dark, .large), ("Accessibility", .dark, .accessibility5)] {
            let renderer = ImageRenderer(content: CompanionReviewSheet(scheme: scheme, typeSize: size))
            renderer.scale = 2
            if let data = renderer.uiImage?.pngData() { try? data.write(to: directory.appendingPathComponent("Companion-\(name).png")) }
            for phase in [SuzzmeLiveActivityPhase.checking, .understanding, .speaking, .summaryReady, .confirmation, .completed] {
                let card = SuzzmeCompanionActivityCard(phase: phase, motionEnabled: false)
                    .frame(width: 374).environment(\.colorScheme, scheme).dynamicTypeSize(size)
                let measured = ImageRenderer(content: card)
                measured.scale = 1
                heights["\(name)-\(phase.rawValue)"] = measured.uiImage.map { Double($0.size.height) }
            }
        }
        if let data = try? JSONEncoder().encode(heights) { try? data.write(to: directory.appendingPathComponent("card-heights.json")) }
    }
}
