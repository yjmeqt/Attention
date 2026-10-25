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

struct CardMetrics {
    let aspect: CardAspect

    var size: CGSize { aspect.size }
    var padding: CGFloat { 18 }

    /// Banner height that shows the whole image when possible, within limits that keep room for the text.
    func heroImageHeight(for ratio: CGFloat?) -> CGFloat {
        let range: ClosedRange<CGFloat> = switch aspect {
        case .portrait: 150...250
        case .square: 110...140
        case .story: 200...400
        }
        let middle = (range.lowerBound + range.upperBound) / 2
        guard let ratio, ratio > 0 else { return middle }
        let natural = size.width / ratio
        // Too tall to show whole; HeroImage letterboxes it, so a medium banner leaves more room for the title.
        if natural > range.upperBound { return middle }
        return max(natural, range.lowerBound)
    }

    func heroTitleLines(imageHeight: CGFloat, hasByline: Bool) -> Int {
        let body = size.height - imageHeight - padding * 2
        let footer = footerQRSize + 33
        let byline: CGFloat = hasByline ? 24 : 0
        let lines = Int((body - footer - byline - 14) / 28)
        return min(max(lines, 1), 8)
    }

    func postMediaHeight(for ratio: CGFloat?) -> CGFloat {
        let maxHeight: CGFloat = switch aspect {
        case .portrait: 150
        case .square: 0
        case .story: 260
        }
        guard maxHeight > 0, let ratio, ratio > 0 else { return 0 }
        return min(max((size.width - padding * 2) / ratio, 100), maxHeight)
    }

    func postLines(withMedia: Bool) -> Int {
        switch aspect {
        case .portrait: withMedia ? 3 : 8
        case .square: 5
        case .story: withMedia ? 7 : 15
        }
    }

    var minimalLines: Int {
        switch aspect {
        case .portrait: 6
        case .square: 3
        case .story: 10
        }
    }

    var footerQRSize: CGFloat {
        switch aspect {
        case .portrait: 80
        case .square: 72
        case .story: 112
        }
    }

    var bigQRSize: CGFloat {
        switch aspect {
        case .portrait: 180
        case .square: 130
        case .story: 220
        }
    }
}
