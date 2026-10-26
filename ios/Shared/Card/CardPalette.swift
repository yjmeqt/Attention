import SwiftUI

struct CardPalette {
    let background: Color
    let primary: Color
    let secondary: Color
    let tertiary: Color
    let accent: Color
    let onAccent: Color

    init(kind: LinkKind) {
        background = .white
        primary = Color(red: 0.07, green: 0.07, blue: 0.08)
        secondary = primary.opacity(0.62)
        tertiary = primary.opacity(0.38)
        switch kind {
        case .youtube:
            accent = Color(red: 1, green: 0, blue: 0.2)
            onAccent = .white
        case .bilibili:
            accent = Color(red: 0.98, green: 0.45, blue: 0.6)
            onAccent = .white
        case .x:
            accent = .black
            onAccent = .white
        case .web:
            accent = Color(red: 0.18, green: 0.42, blue: 1)
            onAccent = .white
        }
    }
}

/// Sizes for the Text and QR templates, which are as tall as their content.
enum CardMetrics {
    static let minimalLines = 6
    static let footerQRSize: CGFloat = 80
    static let bigQRSize: CGFloat = 180
}
