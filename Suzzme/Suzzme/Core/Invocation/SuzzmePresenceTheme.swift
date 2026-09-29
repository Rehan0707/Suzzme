import SwiftUI

/// Curated visual choices for active intelligence surfaces only. They do not
/// affect Suzzme's reasoning, memory, or normal application chrome.
enum SuzzmePresenceTheme: String, CaseIterable, Codable, Sendable, Identifiable {
    case suzzmePurple, burgundy, deepBlue, silver, graphite

    var id: Self { self }
    var title: String {
        switch self {
        case .suzzmePurple: "Suzzme Purple"
        case .burgundy: "Burgundy"
        case .deepBlue: "Deep Blue"
        case .silver: "Silver"
        case .graphite: "Graphite"
        }
    }

    var accessibilityName: String { "\(title) presence theme" }

    func colors(for scheme: ColorScheme) -> SuzzmePresenceColors {
        switch self {
        case .suzzmePurple:
            .init(primary: SuzzmeTheme.lavender, secondary: SuzzmeTheme.lilac, highlight: Color(red: 0.62, green: 0.39, blue: 0.93), glow: Color(red: 0.76, green: 0.55, blue: 0.91), face: scheme == .dark ? .white : .black)
        case .burgundy:
            .init(primary: Color(red: 0.50, green: 0.12, blue: 0.23), secondary: Color(red: 0.76, green: 0.30, blue: 0.38), highlight: Color(red: 0.94, green: 0.57, blue: 0.54), glow: Color(red: 0.62, green: 0.18, blue: 0.32), face: scheme == .dark ? .white : .black)
        case .deepBlue:
            .init(primary: Color(red: 0.08, green: 0.25, blue: 0.57), secondary: Color(red: 0.22, green: 0.52, blue: 0.93), highlight: Color(red: 0.52, green: 0.77, blue: 1), glow: Color(red: 0.12, green: 0.39, blue: 0.82), face: scheme == .dark ? .white : .black)
        case .silver:
            .init(primary: scheme == .dark ? Color(red: 0.62, green: 0.66, blue: 0.72) : Color(red: 0.38, green: 0.42, blue: 0.49), secondary: Color(red: 0.82, green: 0.86, blue: 0.91), highlight: Color.white, glow: Color(red: 0.72, green: 0.78, blue: 0.88), face: scheme == .dark ? .white : .black)
        case .graphite:
            .init(primary: scheme == .dark ? Color(red: 0.56, green: 0.60, blue: 0.67) : Color(red: 0.17, green: 0.19, blue: 0.24), secondary: Color(red: 0.42, green: 0.46, blue: 0.54), highlight: scheme == .dark ? Color(red: 0.88, green: 0.90, blue: 0.96) : Color(red: 0.40, green: 0.24, blue: 0.59), glow: Color(red: 0.40, green: 0.42, blue: 0.52), face: scheme == .dark ? .white : .black)
        }
    }
}

struct SuzzmePresenceColors {
    let primary: Color
    let secondary: Color
    let highlight: Color
    let glow: Color
    let face: Color
}

enum SuzzmePresenceAnimation: String, CaseIterable, Codable, Sendable, Identifiable {
    case gentle, flow, pulse, minimal

    var id: Self { self }
    var title: String { rawValue.capitalized }
    var duration: Double {
        switch self {
        case .gentle: 2.5
        case .flow: 1.9
        case .pulse: 1.35
        case .minimal: 0
        }
    }
}
