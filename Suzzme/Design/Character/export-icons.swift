import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Platform-size exports of the generated master, with opaque RGB icon output.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let masterURL = directory.appendingPathComponent("Design/Character/SuzzmeAppIcon-Master.png")
guard let source = CGImageSourceCreateWithURL(masterURL as CFURL, nil),
      let master = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Missing icon master") }
let catalog = directory.appendingPathComponent("Suzzme/Assets.xcassets/AppIcon.appiconset")
let exports: [(String, Int)] = [("SuzzmeIcon-iOS-Default-1024@1x.png", 1024)]
    + [16, 32, 64, 128, 256, 512, 1024].map { ("SuzzmeIcon-mac-\($0).png", $0) }
func export(_ image: CGImage, filename: String, destinationDirectory: URL,
            size: Int, drawRect: CGRect? = nil) {
    guard let context = CGContext(data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { fatalError("Cannot create icon context") }
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(rect)
    context.interpolationQuality = .high
    context.draw(image, in: drawRect ?? rect)
    guard let output = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(destinationDirectory.appendingPathComponent(filename) as CFURL,
            UTType.png.identifier as CFString, 1, nil) else { fatalError("Cannot export icon") }
    CGImageDestinationAddImage(destination, output, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write icon") }
}

for (filename, size) in exports {
    export(master, filename: filename, destinationDirectory: catalog, size: size)
}

let supplied = directory.appendingPathComponent("Design/Character/Supplied")
let alternateNames = ["Pink", "Red", "Orange", "Yellow", "Green", "Teal", "Purple"]
for name in alternateNames {
    let sourceURL = supplied.appendingPathComponent("char_\(name.lowercased()).png")
    guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
          let character = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Missing supplied \(name.lowercased()) character artwork")
    }
    let assetName = "AppIcon\(name)"
    let assetDirectory = directory.appendingPathComponent("Suzzme/Assets.xcassets/\(assetName).appiconset")
    try! FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
    // The supplied character art has the same transparent canvas and bounds
    // in each color. Fit it to the cloud's established icon framing.
    let drawRect = CGRect(x: -61, y: -33, width: 1148, height: 1122)
    let iconFilename = "\(assetName)-1024.png"
    export(character, filename: iconFilename, destinationDirectory: assetDirectory,
           size: 1024, drawRect: drawRect)
    let contents = """
    {"images":[{"filename":"\(iconFilename)","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
    """
    try! contents.write(to: assetDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
print("Exported \(exports.count) primary icon sizes and \(alternateNames.count) mascot-colored iOS alternate icons.")
