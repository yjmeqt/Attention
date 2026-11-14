import SwiftUI

/// Animated walkthrough of saving a link copied in another app: open Attention and tap Paste on the banner.
struct CopyGuide: View {
    var onWatched: (() -> Void)? = nil
    @State private var phase: Phase = .page
    @State private var target: GuideTarget?
    @State private var pressing = false
    @State private var run = 0

    enum Phase: Int, CaseIterable {
        case page, sheet, banner, saved

        var target: GuideTarget? {
            switch self {
            case .page: .share
            case .sheet: .copy
            case .banner: .paste
            case .saved: nil
            }
        }

        var caption: String {
            switch self {
            case .page: String(localized: "Tap the Share button")
            case .sheet: String(localized: "Tap Copy")
            case .banner: String(localized: "Open \(Brand.name) and tap Paste")
            case .saved: String(localized: "Your link is saved as a card")
            }
        }

        var showsLibrary: Bool { self == .banner || self == .saved }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                stage
                captions
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(String(localized: "Copy and Paste"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: run) { await play() }
    }

    private var stage: some View {
        ZStack(alignment: .bottom) {
            GuideSourcePage()
            // Switching apps: the library slides over the page the link was copied from.
            if phase.showsLibrary {
                GuideLibrary(saved: phase == .saved)
                    .transition(.move(edge: .trailing))
                    .zIndex(1)
            }
            if phase == .sheet {
                Color.black.opacity(0.25).transition(.opacity).zIndex(2)
                GuideShareSheet()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(3)
            }
        }
        .frame(width: 290, height: 560)
        .clipShape(.rect(cornerRadius: 44, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .strokeBorder(.secondary.opacity(0.35), lineWidth: 5)
        }
        .overlayPreferenceValue(GuideTargetKey.self) { anchors in
            GeometryReader { proxy in
                if let target, let anchor = anchors[target] {
                    TouchDot(pressing: pressing)
                        .position(proxy[anchor])
                        .transition(.opacity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Phase.allCases.map(\.caption).joined(separator: ". "))
    }

    private var captions: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(Phase.allCases, id: \.self) { p in
                    Capsule()
                        .fill(p == phase ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary))
                        .frame(width: p == phase ? 18 : 6, height: 6)
                }
            }
            Text(phase.caption)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(minHeight: 48)
                .contentTransition(.opacity)
            Button(String(localized: "Replay"), systemImage: "arrow.counterclockwise") { run += 1 }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: 340)
    }

    private func play() async {
        while !Task.isCancelled {
            withAnimation(.smooth) { phase = .page; target = nil }
            guard await pause(0.8) else { return }
            for p in Phase.allCases.dropLast() {
                withAnimation(.smooth(duration: 0.6)) { target = p.target }
                guard await pause(0.9) else { return }
                withAnimation(.easeIn(duration: 0.12)) { pressing = true }
                guard await pause(0.16) else { return }
                withAnimation(.easeOut(duration: 0.2)) { pressing = false }
                let next = Phase(rawValue: p.rawValue + 1) ?? .saved
                withAnimation(.snappy(duration: 0.45)) {
                    phase = next
                    if next == .saved { target = nil }
                }
                if next == .saved { onWatched?() }
                guard await pause(1.3) else { return }
            }
            guard await pause(2.4) else { return }
        }
    }

    private func pause(_ seconds: Double) async -> Bool {
        (try? await Task.sleep(for: .seconds(seconds))) != nil
    }
}


nonisolated enum GuideTarget: Hashable, Sendable {
    case share, copy, paste
}

nonisolated struct GuideTargetKey: PreferenceKey {
    static let defaultValue: [GuideTarget: Anchor<CGPoint>] = [:]
    static func reduce(value: inout [GuideTarget: Anchor<CGPoint>], nextValue: () -> [GuideTarget: Anchor<CGPoint>]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension View {
    func guideTarget(_ target: GuideTarget) -> some View {
        anchorPreference(key: GuideTargetKey.self, value: .center) { [target: $0] }
    }
}

private struct TouchDot: View {
    let pressing: Bool

    var body: some View {
        Circle()
            .fill(.white.opacity(0.55))
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .frame(width: 40, height: 40)
            .shadow(color: .black.opacity(0.3), radius: 6)
            .scaleEffect(pressing ? 0.7 : 1)
            .allowsHitTesting(false)
    }
}

// MARK: - Mock screens

private struct GuideSourcePage: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [.red.opacity(0.8), .orange.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 150)
                    .overlay { Image(systemName: "play.fill").font(.largeTitle).foregroundStyle(.white) }
                Text(verbatim: "WWDC 2025 Keynote")
                    .font(.headline)
                ForEach([1.0, 0.9, 0.95, 0.6], id: \.self) { w in
                    Capsule().fill(.fill.secondary).frame(height: 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaleEffect(x: w, anchor: .leading)
                }
            }
            .padding(.top, 56)
            .padding(.horizontal, 18)
            Spacer()
            HStack {
                Image(systemName: "chevron.left")
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.tint)
                    .guideTarget(.share)
                Spacer()
                Image(systemName: "book")
                Spacer()
                Image(systemName: "square.on.square")
            }
            .font(.title3)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 30)
            .padding(.top, 14)
            .padding(.bottom, 34)
            .background(.bar)
        }
        .background(Color(.systemBackground))
    }
}

/// Attention's library with the banner that offers the copied link, then the card it was saved as.
private struct GuideLibrary: View {
    let saved: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                AttentionGlyph(size: 26)
                Text(Brand.name).font(.title3.bold())
                Spacer(minLength: 0)
            }
            .padding(.top, 56)
            .padding(.horizontal, 18)

            HStack(alignment: .top, spacing: 10) {
                ForEach([[120.0, 150, 90], [150.0, 100, 110]], id: \.self) { heights in
                    VStack(spacing: 10) {
                        ForEach(heights, id: \.self) { height in
                            RoundedRectangle(cornerRadius: 12).fill(.fill.tertiary).frame(height: height)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .frame(maxHeight: .infinity, alignment: .top)
            .opacity(saved ? 0.35 : 1)
            .overlay {
                if saved {
                    SampleCard(scale: 0.55)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }

            if !saved {
                banner.transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 26)
        .background(Color(.systemBackground))
    }

    private var banner: some View {
        HStack(spacing: 8) {
            Label("You copied a link", systemImage: "link")
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Label(String(localized: "Paste"), systemImage: "doc.on.clipboard")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.tint, in: .capsule)
                .fixedSize()
                .guideTarget(.paste)
            Image(systemName: "xmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: .capsule)
        .overlay(Capsule().strokeBorder(.secondary.opacity(0.2)))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        .padding(.horizontal, 12)
    }
}

private struct GuideShareSheet: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.red.gradient)
                    .frame(width: 44, height: 44)
                    .overlay { Image(systemName: "play.fill").foregroundStyle(.white) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "WWDC 2025 Keynote").font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("youtube.com").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Divider()
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    Circle().fill(.fill.secondary).frame(width: 50, height: 50)
                }
            }
            Divider()
            HStack(alignment: .top, spacing: 8) {
                GuideAppCell(app: .messages)
                GuideAppCell(app: .mail)
                GuideAppCell(app: .wechat)
                GuideAppCell(app: .more)
            }
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "doc.on.doc")
                    .frame(width: 50, height: 50)
                    .background(.fill.tertiary, in: .circle)
                    .guideTarget(.copy)
                ForEach(["person.crop.circle.badge.plus", "eyeglasses", "chevron.down"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .frame(width: 50, height: 50)
                        .background(.fill.tertiary, in: .circle)
                }
            }
            .foregroundStyle(.primary)
        }
        .padding(16)
        .padding(.bottom, 10)
        .background(.regularMaterial, in: .rect(cornerRadius: 34, style: .continuous))
        .padding(8)
    }
}

private struct GuideAppCell: View {
    let app: GuideApp

    var body: some View {
        VStack(spacing: 5) {
            app.icon(size: 50)
            Text(app.name)
                .font(.caption2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 54)
        }
    }
}

private enum GuideApp {
    case messages, mail, wechat, more

    var name: String {
        switch self {
        case .messages: String(localized: "Messages")
        case .mail: String(localized: "Mail")
        case .wechat: String(localized: "WeChat")
        case .more: String(localized: "More")
        }
    }

    @ViewBuilder func icon(size: CGFloat) -> some View {
        switch self {
        case .messages: tile("message.fill", .green, size)
        case .mail: tile("envelope.fill", .blue, size)
        case .wechat: tile("bubble.left.and.bubble.right.fill", Color(red: 0.03, green: 0.76, blue: 0.38), size)
        case .more:
            Image(systemName: "ellipsis")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
                .background(Color(.systemBackground), in: .rect(cornerRadius: size * 0.225, style: .continuous))
        }
    }

    private func tile(_ symbol: String, _ color: Color, _ size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.225, style: .continuous))
    }
}

#Preview {
    NavigationStack { CopyGuide() }
}
