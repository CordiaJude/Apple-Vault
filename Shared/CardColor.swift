import SwiftUI

/// The palette shared by document cards, people and widgets.
nonisolated enum CardColor: String, CaseIterable, Codable, Identifiable, Sendable {
    case blue, indigo, purple, pink, red, orange, yellow, green, mint, teal, sky, brown, graphite

    var id: String { rawValue }

    var name: String {
        switch self {
        case .blue: String(localized: "Blue")
        case .indigo: String(localized: "Indigo")
        case .purple: String(localized: "Purple")
        case .pink: String(localized: "Pink")
        case .red: String(localized: "Red")
        case .orange: String(localized: "Orange")
        case .yellow: String(localized: "Yellow")
        case .green: String(localized: "Green")
        case .mint: String(localized: "Mint")
        case .teal: String(localized: "Teal")
        case .sky: String(localized: "Sky")
        case .brown: String(localized: "Brown")
        case .graphite: String(localized: "Graphite")
        }
    }

    /// Hand-tuned top and bottom gradient stops, in the spirit of Wallet passes:
    /// saturated, but deep enough that white text always passes contrast.
    private var stops: (top: (Double, Double, Double), bottom: (Double, Double, Double)) {
        switch self {
        case .blue: ((0.20, 0.52, 0.98), (0.04, 0.27, 0.78))
        case .indigo: ((0.40, 0.40, 0.95), (0.20, 0.18, 0.66))
        case .purple: ((0.66, 0.38, 0.92), (0.38, 0.16, 0.66))
        case .pink: ((0.98, 0.38, 0.60), (0.74, 0.12, 0.38))
        case .red: ((0.96, 0.33, 0.30), (0.70, 0.10, 0.12))
        case .orange: ((1.00, 0.58, 0.20), (0.86, 0.32, 0.04))
        case .yellow: ((0.98, 0.76, 0.18), (0.82, 0.52, 0.02))
        case .green: ((0.26, 0.78, 0.40), (0.06, 0.50, 0.24))
        case .mint: ((0.22, 0.80, 0.72), (0.03, 0.52, 0.48))
        case .teal: ((0.20, 0.66, 0.78), (0.03, 0.40, 0.52))
        case .sky: ((0.36, 0.74, 0.98), (0.10, 0.46, 0.80))
        case .brown: ((0.66, 0.50, 0.38), (0.40, 0.27, 0.18))
        case .graphite: ((0.44, 0.46, 0.50), (0.18, 0.19, 0.22))
        }
    }

    var color: Color {
        let c = stops.top
        let d = stops.bottom
        return Color(red: (c.0 + d.0) / 2, green: (c.1 + d.1) / 2, blue: (c.2 + d.2) / 2)
    }

    var topColor: Color { Color(red: stops.top.0, green: stops.top.1, blue: stops.top.2) }
    var bottomColor: Color { Color(red: stops.bottom.0, green: stops.bottom.1, blue: stops.bottom.2) }

    var gradient: LinearGradient {
        LinearGradient(colors: [topColor, bottomColor], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Yellow and mint cards read better with dark text, like their Wallet counterparts.
    var prefersDarkForeground: Bool { self == .yellow }
}
