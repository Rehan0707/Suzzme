import SwiftUI
import ImageIO
import Observation

enum SuzzmeMascotColor: String, CaseIterable, Identifiable, Sendable {
    case blue, pink, red, orange, yellow, green, teal, purple

    static let defaultsKey = "suzzme.mascot.color"
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var assetName: String { "SuzzmeMascot\(title)" }
    var animationName: String { "speaking_\(rawValue)" }

    /// A saturated companion accent keeps labels and controls legible while
    /// the original pastel character artwork remains unchanged.
    var accent: Color {
        switch self {
        case .blue: Color(red: 0.12, green: 0.43, blue: 0.82)
        case .pink: Color(red: 0.69, green: 0.20, blue: 0.43)
        case .red: Color(red: 0.76, green: 0.22, blue: 0.27)
        case .orange: Color(red: 0.72, green: 0.34, blue: 0.12)
        case .yellow: Color(red: 0.54, green: 0.40, blue: 0.04)
        case .green: Color(red: 0.16, green: 0.48, blue: 0.20)
        case .teal: Color(red: 0.02, green: 0.48, blue: 0.46)
        case .purple: Color(red: 0.48, green: 0.25, blue: 0.70)
        }
    }

    var secondaryAccent: Color { accent.opacity(0.72) }
    var highlight: Color { accent.opacity(0.46) }
    var surfaceTint: Color { accent.opacity(0.085) }
    var appIconName: String? { self == .blue ? nil : "AppIcon\(title)" }

    /// Sampled body colors keep native eyelids consistent with the supplied art.
    var eyelid: Color {
        let rgb: (Double, Double, Double) = switch self {
        case .blue: (125, 188, 249)
        case .pink: (249, 125, 184)
        case .red: (249, 125, 132)
        case .orange: (249, 169, 125)
        case .yellow: (249, 221, 125)
        case .green: (127, 249, 125)
        case .teal: (125, 249, 226)
        case .purple: (194, 125, 249)
        }
        return Color(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255)
    }
}

/// Observable semantic theme source. Static SuzzmeTheme colors read this
/// property, so the existing screens repaint when the selected mascot changes.
@MainActor @Observable
final class SuzzmeMascotAppearance {
    static let shared = SuzzmeMascotAppearance()

    private(set) var color: SuzzmeMascotColor

    private init() {
        color = SuzzmeMascotColor(rawValue:
            UserDefaults.standard.string(forKey: SuzzmeMascotColor.defaultsKey) ?? "blue") ?? .blue
    }

    func select(_ color: SuzzmeMascotColor) {
        guard self.color != color else { return }
        self.color = color
        UserDefaults.standard.set(color.rawValue, forKey: SuzzmeMascotColor.defaultsKey)
    }

    func synchronizeStoredColor(_ rawValue: String) {
        select(SuzzmeMascotColor(rawValue: rawValue) ?? .blue)
    }
}

struct SuzzmeMascotFrames: Sendable {
    let images: [CGImage]
    let ends: [Double]
    var duration: Double { ends.last ?? 0 }

    func index(at elapsed: Double) -> Int {
        guard elapsed.isFinite, duration > 0 else { return 0 }
        let position = max(elapsed, 0).truncatingRemainder(dividingBy: duration)
        return ends.firstIndex(where: { position < $0 }) ?? 0
    }
}

/// One bounded, shared decoded sequence. Concurrent presence surfaces share
/// the same load; a color change retires the old cache rather than retaining
/// all eight full-size animations. No audio or assistant state is created here.
actor SuzzmeMascotAnimationCache {
    static let shared = SuzzmeMascotAnimationCache()
    private var cachedName: String?
    private var cached: SuzzmeMascotFrames?
    private var pending: (name: String, id: UUID, task: Task<SuzzmeMascotFrames?, Never>)?

    func frames(named name: String, fileExtension: String = "gif") async -> SuzzmeMascotFrames? {
        guard !Task.isCancelled else { return nil }
        let key = "\(name).\(fileExtension)"
        if cachedName == key { return cached }
        if let pending, pending.name == key { return await pending.task.value }
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else { return nil }
        pending?.task.cancel()
        let id = UUID()
        let task = Task { await Self.decode(url: url) }
        pending = (key, id, task)
        let frames = await task.value
        if pending?.id == id {
            cachedName = key
            cached = frames
            pending = nil
        }
        return frames
    }

    @concurrent private static func decode(url: URL) async -> SuzzmeMascotFrames? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0, count <= 60 else { return nil }
        var images: [CGImage] = []
        var ends: [Double] = []
        var total = 0.0
        for index in 0..<count {
            guard !Task.isCancelled,
                  let image = CGImageSourceCreateThumbnailAtIndex(source, index, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 520,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return nil }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? NSNumber)?.doubleValue
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? NSNumber)?.doubleValue ?? 0.1
            total += delay.isFinite ? min(max(delay, 0.02), 1) : 0.1
            let isPose = ["wave_", "think_", "sleep_"].contains { url.deletingPathExtension().lastPathComponent.hasPrefix($0) }
            images.append(isPose ? SuzzmePoseCutout.removeBackground(from: image) ?? image : image)
            ends.append(total)
        }
        return .init(images: images, ends: ends)
    }
}

/// The supplied pose frames have an opaque cream backdrop. Remove only the
/// near-cream region connected to an edge; disconnected white eyes stay intact.
private enum SuzzmePoseCutout {
    static func removeBackground(from image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drew = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        var visited = [UInt8](repeating: 0, count: width * height)
        var queue: [Int] = []
        func enqueue(_ index: Int) {
            guard visited[index] == 0 else { return }
            visited[index] = 1
            let offset = index * 4
            guard pixels[offset] >= 205, pixels[offset + 1] >= 200,
                  pixels[offset + 2] >= 190 else { return }
            queue.append(index)
        }
        for x in 0..<width {
            enqueue(x)
            enqueue((height - 1) * width + x)
        }
        for y in 0..<height {
            enqueue(y * width)
            enqueue(y * width + width - 1)
        }
        var head = 0
        while head < queue.count {
            let index = queue[head]
            head += 1
            let x = index % width
            if x > 0 { enqueue(index - 1) }
            if x + 1 < width { enqueue(index + 1) }
            if index >= width { enqueue(index - width) }
            if index + width < width * height { enqueue(index + width) }
        }
        for index in queue {
            let offset = index * 4
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 0
        }
        return pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return nil }
            return context.makeImage()
        }
    }
}

struct SuzzmeSpeakingArtwork: View {
    let frames: SuzzmeMascotFrames
    let maskAsset: String
    @State private var startedAt = Date()

    var body: some View {
        // Supplied GIFs are 16 frames at 90 ms. Their actual timing is retained.
        // This subtree exists only during real speech and allowed motion.
        TimelineView(.periodic(from: startedAt, by: 0.09)) { context in
            SuzzmeSpeakingFrame(image: frames.images[frames.index(at: context.date.timeIntervalSince(startedAt))],
                                maskAsset: maskAsset)
        }
        .accessibilityHidden(true)
    }
}

struct SuzzmeAnimatedPoseArtwork: View {
    let frames: SuzzmeMascotFrames
    let loops: Bool
    @State private var startedAt = Date()
    @State private var finished = false

    var body: some View {
        Group {
            if finished, !loops, let lastFrame = frames.images.last {
                Image(decorative: lastFrame, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                TimelineView(.periodic(from: startedAt, by: 0.09)) { context in
                    let elapsed = context.date.timeIntervalSince(startedAt)
                    Image(decorative: frames.images[frames.index(at: elapsed)], scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }
            }
        }
        .task {
            guard !loops else { return }
            do { try await Task.sleep(for: .seconds(frames.duration)) } catch { return }
            guard !Task.isCancelled else { return }
            finished = true
        }
        .accessibilityHidden(true)
    }
}

struct SuzzmeSpeakingFrame: View {
    let image: CGImage
    let maskAsset: String

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFit()
            .mask {
                // White eyes stay opaque: only the supplied PNG's alpha
                // controls the silhouette, never a global white color key.
                Image(maskAsset).resizable().scaledToFit()
            }
    }
}
