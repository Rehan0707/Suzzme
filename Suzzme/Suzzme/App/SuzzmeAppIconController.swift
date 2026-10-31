import SwiftUI
import os
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Keeps the platform app icon paired with the selected companion color.
@MainActor enum SuzzmeAppIconController {
    private static let logger = Logger(subsystem: "Suzzme", category: "MascotAppearance")

    #if os(iOS)
    static func apply(_ color: SuzzmeMascotColor) async {
        let iconName = color.appIconName
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != iconName else { return }
        do {
            try await UIApplication.shared.setAlternateIconName(iconName)
        } catch {
            logger.error("The Home Screen icon could not be updated: \(error.localizedDescription, privacy: .public)")
        }
    }
    #elseif os(macOS)
    static func apply(_ color: SuzzmeMascotColor) {
        NSApplication.shared.applicationIconImage = color == .blue
            ? nil
            : NSImage(named: NSImage.Name(color.assetName))
    }
    #endif
}
