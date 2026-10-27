#!/usr/bin/env swift
// Frames raw simulator screenshots (ios/fastlane/raw) with a caption for App Store Connect.
// Output: ios/fastlane/screenshots/<locale>/<device>-<scene>.png at the required pixel sizes.
// Run from ios/: swift Tools/frame-screenshots.swift
import AppKit

// Each caption is a bold lead and a plain rest: `**lead.** rest`.
let captions: [String: [String: String]] = [
    "en-US": [
        "1-feed": "**Everything you save.** Links from every app, gathered in one calm feed.",
        "2-share": "**Save from any app.** Tap Share, then Attention.",
        "3-detail": "**Share it as a card.** Or as clean text, ready for any chat.",
        "4-private": "**Private, behind Face ID.** No account, no tracking. It stays on your device.",
    ],
    "zh-Hans": [
        "1-feed": "**想看的，都在这里。**各个 App 里存下的链接，汇成一条安静的信息流。",
        "2-share": "**任何 App 都能存。**点分享，再点 Attention。",
        "3-detail": "**分享成一张卡片。**也可以是简洁的文字卡，发到哪儿都好看。",
        "4-private": "**私密内容，面容 ID 锁住。**无需账号，没有追踪，只存在你的设备上。",
    ],
    "ko": [
        "1-feed": "**저장한 모든 것.** 모든 앱의 링크를 하나의 차분한 피드에.",
        "2-share": "**어떤 앱에서든 저장.** 공유를 누르고 Attention을 탭하세요.",
        "3-detail": "**카드로 공유하세요.** 깔끔한 텍스트 카드로도 보낼 수 있어요.",
        "4-private": "**비공개 항목은 Face ID로.** 계정도, 추적도 없이 기기에만 저장돼요.",
    ],
    "ja": [
        "1-feed": "**保存したものを、ひとつに。**どのアプリのリンクも、静かなフィードにまとまります。",
        "2-share": "**どのアプリからでも保存。**共有をタップして、Attention を選ぶだけ。",
        "3-detail": "**カードにして共有。**シンプルなテキストカードでも。",
        "4-private": "**プライベートは Face ID で。**アカウント不要、トラッキングなし。データは端末の中だけ。",
    ],
    "ru": [
        "1-feed": "**Всё, что вы сохранили.** Ссылки из любых приложений в одной спокойной ленте.",
        "2-share": "**Сохраняйте из любого приложения.** Нажмите «Поделиться», затем Attention.",
        "3-detail": "**Делитесь карточкой.** Или аккуратной текстовой.",
        "4-private": "**Личное — под Face ID.** Без аккаунта и отслеживания. Всё хранится на устройстве.",
    ],
    "vi": [
        "1-feed": "**Mọi thứ bạn đã lưu.** Liên kết từ mọi ứng dụng, gom vào một dòng tin yên tĩnh.",
        "2-share": "**Lưu từ mọi ứng dụng.** Chạm Chia sẻ, rồi chọn Attention.",
        "3-detail": "**Chia sẻ dưới dạng thẻ.** Hoặc thẻ chữ gọn gàng.",
        "4-private": "**Riêng tư, khóa bằng Face ID.** Không tài khoản, không theo dõi. Dữ liệu chỉ ở trên máy bạn.",
    ],
    "ar-SA": [
        "1-feed": "**كل ما تحفظه.** روابط من كل التطبيقات في موجز هادئ واحد.",
        "2-share": "**احفظ من أي تطبيق.** اضغط مشاركة، ثم Attention.",
        "3-detail": "**شاركه كبطاقة.** أو كبطاقة نصية بسيطة.",
        "4-private": "**خصوصيتك خلف Face ID.** بلا حساب وبلا تتبع. تبقى بياناتك على جهازك.",
    ],
    "fr-FR": [
        "1-feed": "**Tout ce que vous gardez.** Les liens de chaque app, réunis dans un fil paisible.",
        "2-share": "**Enregistrez depuis n’importe quelle app.** Touchez Partager, puis Attention.",
        "3-detail": "**Partagez-le en carte.** Ou en carte texte, toute simple.",
        "4-private": "**Le privé, derrière Face ID.** Sans compte, sans pistage. Tout reste sur votre appareil.",
    ],
    "de-DE": [
        "1-feed": "**Alles, was du sicherst.** Links aus jeder App, gesammelt in einem ruhigen Feed.",
        "2-share": "**Aus jeder App sichern.** Auf Teilen tippen, dann auf Attention.",
        "3-detail": "**Als Karte teilen.** Oder als schlichte Textkarte.",
        "4-private": "**Privates hinter Face ID.** Kein Konto, kein Tracking. Alles bleibt auf deinem Gerät.",
    ],
    "es-ES": [
        "1-feed": "**Todo lo que guardas.** Enlaces de cualquier app, reunidos en un feed tranquilo.",
        "2-share": "**Guarda desde cualquier app.** Toca Compartir y luego Attention.",
        "3-detail": "**Compártelo como tarjeta.** O como una tarjeta de texto sencilla.",
        "4-private": "**Lo privado, tras Face ID.** Sin cuenta, sin rastreo. Todo se queda en tu dispositivo.",
    ],
]
// Locales that reuse another locale's framed screenshots.
let aliases = ["es-MX": "es-ES"]
let rightToLeft: Set = ["ar-SA"]
/// No spaces to break at, so the rest of the caption starts on its own line.
let unspaced: Set = ["zh-Hans", "ja"]

struct Layout {
    let canvas: CGSize
    let shotWidth: CGFloat
    let textSize: CGFloat
    /// The caption's top margin, its width as a fraction of the canvas, and the most lines it may take.
    let textTop: CGFloat
    let textWidth: CGFloat
    let lines: CGFloat
    /// Space between the caption and the device, which runs off the bottom of the canvas.
    let gap: CGFloat
    let cornerRadius: CGFloat
    /// How much larger the lifted-out element is drawn.
    let popScale: CGFloat
    /// The screen's left corners, where they differ: the Duo's outer display meets the hinge there.
    var leftCornerRadius: CGFloat? = nil
}

let layouts: [String: Layout] = [
    "iphone": Layout(canvas: CGSize(width: 1320, height: 2868), shotWidth: 1120, textSize: 86, textTop: 190, textWidth: 0.85,
                     lines: 3, gap: 110, cornerRadius: 150, popScale: 1.9),
    "ipad": Layout(canvas: CGSize(width: 2752, height: 2064), shotWidth: 2240, textSize: 80, textTop: 130, textWidth: 0.62,
                   lines: 2, gap: 90, cornerRadius: 44, popScale: 2.5),
    "duo": Layout(canvas: CGSize(width: 2007, height: 2853), shotWidth: 1700, textSize: 100, textTop: 200, textWidth: 0.82,
                  lines: 3, gap: 120, cornerRadius: 92, popScale: 1.9),
    // The Duo's outer display, folded: short for a phone, so a smaller caption, two lines in most languages.
    "duo-cover": Layout(canvas: CGSize(width: 1398, height: 2034), shotWidth: 1180, textSize: 76, textTop: 150, textWidth: 0.86,
                        lines: 3, gap: 100, cornerRadius: 130, popScale: 1.8, leftCornerRadius: 20),
]
// Every iPhone needs the 6.3-inch size too; it's the 6.9-inch frame scaled down (same aspect ratio).
let scaledCopies = ["iphone": ("iphone63", CGSize(width: 1206, height: 2622))]

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
/// The icon's coral for the set, a little deeper so white text reads on it; Private is the icon's ink.
let coral = srgb(0xD64A33)
let ink = srgb(0x161618)

/// Apple's product bezels (Apple Design Resources, the iOS 27 UI kit's Product Bezels page), exported
/// at full size into fastlane/bezels, which stays out of git. `screen` is where the screenshot goes,
/// in the image's pixels, y from the top. `light` is the silver or white finish, which the dark Private
/// page uses so the device doesn't vanish into it. Without the files the frames draw a plain bezel.
struct DeviceBezel { let image: CGImage; let light: CGImage?; let screen: CGRect }
func image(_ url: URL) -> CGImage? { NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
let bezels: [String: DeviceBezel] = {
    let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "fastlane/bezels")
    let screens = [
        "iphone": CGRect(x: 75, y: 66, width: 1320, height: 2868),   // iPhone 18 Pro Max, Black and Silver
        "ipad": CGRect(x: 124, y: 116, width: 2752, height: 2068),   // iPad Pro 13" (M4), Space Gray and Silver, landscape
        "duo": CGRect(x: 120, y: 120, width: 2007, height: 2853),    // iPhone Duo inner display, Night Sky and Star White, portrait
        "duo-cover": CGRect(x: 88, y: 80, width: 1398, height: 2034), // iPhone Duo outer display, closed, portrait
    ]
    return Dictionary(uniqueKeysWithValues: screens.compactMap { device, screen in
        image(folder.appending(path: "\(device).png")).map {
            (device, DeviceBezel(image: $0, light: image(folder.appending(path: "\(device)-light.png")), screen: screen))
        }
    })
}()

func font(_ size: CGFloat, bold: Bool, locale: String) -> NSFont {
    let name: String? = switch locale {
    case let l where l.hasPrefix("zh"): bold ? "PingFangSC-Semibold" : "PingFangSC-Regular"
    case "ja": bold ? "HiraginoSans-W6" : "HiraginoSans-W3"
    case "ko": bold ? "AppleSDGothicNeo-Bold" : "AppleSDGothicNeo-Regular"
    default: nil
    }
    if let name, let font = NSFont(name: name, size: size) { return font }
    return .systemFont(ofSize: size, weight: bold ? .bold : .regular)
}

/// The lead in bold white, the rest in regular, a little dimmer.
func headline(_ text: String, size: CGFloat, locale: String, rest: NSColor) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for (index, run) in text.components(separatedBy: "**").enumerated() where !run.isEmpty {
        let bold = index % 2 == 1
        let run = !bold && index > 0 && unspaced.contains(locale) ? "\n" + run : run
        result.append(NSAttributedString(string: run, attributes: [
            .font: font(size, bold: bold, locale: locale), .foregroundColor: bold ? NSColor.white : rest, .kern: -size * 0.012,
        ]))
    }
    let style = NSMutableParagraphStyle()
    style.alignment = rightToLeft.contains(locale) ? .right : .left
    style.baseWritingDirection = rightToLeft.contains(locale) ? .rightToLeft : .leftToRight
    style.lineBreakMode = .byWordWrapping
    style.lineHeightMultiple = 1.04
    result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
    return result
}

func height(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
    ceil(text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                           options: [.usesLineFragmentOrigin, .usesFontLeading]).height)
}

/// An element's frame the capture script saved next to a screenshot (Attention's cell in the share
/// sheet, the detail card, the Face ID label), normalized with y from the top.
struct Cell: Decodable { let x, y, width, height: CGFloat }
func frameNextTo(_ raw: URL) -> CGRect? {
    guard let data = try? Data(contentsOf: raw.deletingPathExtension().appendingPathExtension("json")),
          let cell = try? JSONDecoder().decode(Cell.self, from: data), cell.width > 0 else { return nil }
    return CGRect(x: cell.x, y: cell.y, width: cell.width, height: cell.height)
}

/// A rectangle with one corner radius on its left side and another on its right.
func screenShape(_ rect: CGRect, left: CGFloat, right: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX + left, y: rect.maxY))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: right)
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: right)
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: left)
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: left)
    path.closeSubpath()
    return path
}

/// Draws `region` of the canvas again, `scale` times larger and centered at `center`, as a raised tile:
/// one real element lifted out of the screen. `corner` is the tile's corner radius as a share of its
/// shorter side.
func liftOut(_ cg: CGContext, region: CGRect, scale: CGFloat, center: CGPoint, corner: CGFloat = 0.17, _ content: () -> Void) {
    let target = CGRect(x: center.x - region.width * scale / 2, y: center.y - region.height * scale / 2,
                        width: region.width * scale, height: region.height * scale)
    let radius = min(target.width, target.height) * corner
    let shape = CGPath(roundedRect: target, cornerWidth: radius, cornerHeight: radius, transform: nil)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -target.height * 0.04), blur: target.height * 0.22, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    cg.addPath(shape)
    cg.setFillColor(NSColor.black.cgColor)
    cg.fillPath()
    cg.restoreGState()
    cg.saveGState()
    cg.addPath(shape)
    cg.clip()
    cg.translateBy(x: center.x, y: center.y)
    cg.scaleBy(x: scale, y: scale)
    cg.translateBy(x: -region.midX, y: -region.midY)
    content()
    cg.restoreGState()
}

func frame(_ raw: URL, device: String, layout: Layout, scene: String, caption: String, locale: String) -> NSBitmapImageRep? {
    guard let shot = image(raw) else { return nil }
    let size = layout.canvas
    let isPrivate = scene == "4-private"
    // The Duo unlocks with Touch ID, and the capture shows its prompt.
    let touchID = device.hasPrefix("duo")
    let caption = touchID ? caption.replacingOccurrences(of: "Face ID", with: "Touch ID").replacingOccurrences(of: "面容 ID", with: "触控 ID") : caption
    // No alpha channel: App Store Connect rejects screenshots with one.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    cg.interpolationQuality = .high
    let unit = min(size.width, size.height)

    (isPrivate ? ink : coral).setFill()
    CGRect(origin: .zero, size: size).fill()

    // Caption at the top, shrunk until it fits its lines.
    let margin = size.width * 0.075
    let textWidth = size.width * layout.textWidth
    var textSize = layout.textSize
    var text = headline(caption, size: textSize, locale: locale, rest: NSColor.white.withAlphaComponent(isPrivate ? 0.66 : 0.88))
    func lineHeight() -> CGFloat { height(headline("**A**", size: textSize, locale: locale, rest: .white), width: .greatestFiniteMagnitude) }
    while height(text, width: textWidth) > lineHeight() * layout.lines + 1, textSize > 40 {
        textSize -= 2
        text = headline(caption, size: textSize, locale: locale, rest: NSColor.white.withAlphaComponent(isPrivate ? 0.66 : 0.88))
    }
    let textHeight = height(text, width: textWidth)
    let textY = size.height - layout.textTop - textHeight
    let textX = rightToLeft.contains(locale) ? size.width - margin - textWidth : margin
    text.draw(with: CGRect(x: textX, y: textY, width: textWidth, height: textHeight), options: [.usesLineFragmentOrigin, .usesFontLeading])
    let top = size.height - textY + layout.gap

    let product = bezels[device]
    let shotHeight = layout.shotWidth * (product.map { $0.screen.height / $0.screen.width } ?? CGFloat(shot.height) / CGFloat(shot.width))
    let shotRect = CGRect(x: (size.width - layout.shotWidth) / 2, y: size.height - top - shotHeight, width: layout.shotWidth, height: shotHeight)
    func onScreen(_ rect: CGRect) -> CGRect {
        CGRect(x: shotRect.minX + rect.minX * shotRect.width, y: shotRect.maxY - rect.maxY * shotRect.height,
               width: rect.width * shotRect.width, height: rect.height * shotRect.height)
    }

    // The simulator draws the Face ID prompt but not its glyph, so draw the glyph where iOS puts it: the prompt
    // is a square about 1.35 times as wide as its "Face ID" label, which sits along its bottom edge. Where the
    // label is translated and the capture didn't find it, the prompt is in the same place as in English.
    var prompt: CGRect?
    var glyph: (image: NSImage, rect: CGRect)?
    if isPrivate, !touchID {
        let english = raw.deletingLastPathComponent().deletingLastPathComponent().appending(path: "en-US/\(raw.lastPathComponent)")
        if let label = (frameNextTo(raw) ?? frameNextTo(english)).map(onScreen) {
            let side = label.width * 1.35
            prompt = CGRect(x: label.midX - side / 2, y: label.minY - side * 0.16, width: side, height: side)
            let config = NSImage.SymbolConfiguration(pointSize: side * 0.42, weight: .light).applying(.init(paletteColors: [srgb(0xD1D1D6)]))
            if let image = NSImage(systemSymbolName: "faceid", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let center = CGPoint(x: label.midX, y: label.maxY + side * 0.34)
                glyph = (image, CGRect(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2,
                                       width: image.size.width, height: image.size.height))
            }
        }
    }
    func drawScreen() {
        cg.saveGState()
        cg.addPath(screenShape(shotRect, left: layout.leftCornerRadius ?? layout.cornerRadius, right: layout.cornerRadius))
        cg.clip()
        cg.draw(shot, in: shotRect)
        if let glyph { glyph.image.draw(in: glyph.rect) }
        cg.restoreGState()
    }

    drawScreen()
    // Apple's bezel over the screenshot: its screen is cut out, and it carries the Dynamic Island.
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -unit * 0.012), blur: unit * 0.05, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    if let product {
        let scale = layout.shotWidth / product.screen.width
        let rect = CGRect(x: shotRect.minX - product.screen.minX * scale,
                          y: shotRect.maxY + product.screen.minY * scale - CGFloat(product.image.height) * scale,
                          width: CGFloat(product.image.width) * scale, height: CGFloat(product.image.height) * scale)
        cg.draw(isPrivate ? product.light ?? product.image : product.image, in: rect)
    } else {
        let inset = layout.shotWidth * 0.018
        let outer = NSBezierPath(roundedRect: shotRect.insetBy(dx: -inset, dy: -inset), xRadius: layout.cornerRadius + inset, yRadius: layout.cornerRadius + inset)
        outer.appendRoundedRect(shotRect, xRadius: layout.cornerRadius, yRadius: layout.cornerRadius)
        outer.windingRule = .evenOdd
        srgb(0x0B0B0C).setFill()
        outer.fill()
    }
    cg.restoreGState()

    // One element lifted out of the screen, kept within it.
    func keptOnScreen(_ point: CGPoint, _ region: CGRect, _ scale: CGFloat) -> CGPoint {
        let room = shotRect.insetBy(dx: region.width * scale / 2 + unit * 0.03, dy: region.height * scale / 2 + unit * 0.03)
        return CGPoint(x: min(max(point.x, room.minX), room.maxX), y: min(max(point.y, room.minY), room.maxY))
    }
    switch scene {
    case "2-share":
        // Attention in the share sheet, where the capture script found its cell, raised above it
        // (below it on iPad, where the sheet hangs from the top).
        guard let cell = frameNextTo(raw).map(onScreen) else { print("missing share-sheet cell for \(locale)"); break }
        let region = cell.insetBy(dx: -cell.width * 0.12, dy: -cell.height * 0.08)
        let wanted = CGPoint(x: region.midX, y: region.midY + region.height * (device == "ipad" ? -1.2 : 0.9))
        liftOut(cg, region: region, scale: layout.popScale, center: keptOnScreen(wanted, region, layout.popScale), drawScreen)
    case "4-private":
        guard let prompt else { if !touchID { print("missing Face ID label for \(locale)") }; break }
        let region = prompt.insetBy(dx: -prompt.width * 0.14, dy: -prompt.height * 0.14)
        let scale = layout.popScale * 0.95
        liftOut(cg, region: region, scale: scale, center: keptOnScreen(CGPoint(x: region.midX, y: region.midY), region, scale), drawScreen)
    case "3-detail":
        // The card itself, lifted a little off the detail screen so it breaks past the device's edges.
        guard let card = frameNextTo(raw).map(onScreen) else { print("missing card frame for \(locale)"); break }
        liftOut(cg, region: card, scale: 1.16, center: CGPoint(x: card.midX, y: card.midY), corner: 16 / 343, drawScreen)
    default:
        break
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func scaled(_ rep: NSBitmapImageRep, to size: CGSize) -> NSBitmapImageRep {
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
    out.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    NSGraphicsContext.current!.cgContext.interpolationQuality = .high
    NSGraphicsContext.current!.cgContext.draw(rep.cgImage!, in: CGRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    return out
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "fastlane")
let rawRoot = root.appending(path: "raw")

let fileManager = FileManager.default
try? fileManager.removeItem(at: root.appending(path: "screenshots"))

for (locale, scenes) in captions {
    let outDir = root.appending(path: "screenshots").appending(path: locale)
    try fileManager.createDirectory(at: outDir, withIntermediateDirectories: true)
    for (device, layout) in layouts {
        for (scene, caption) in scenes {
            let name = "\(device)-\(scene).png"
            let raw = rawRoot.appending(path: locale).appending(path: name)
            guard fileManager.fileExists(atPath: raw.path),
                  let rep = frame(raw, device: device, layout: layout, scene: scene, caption: caption, locale: locale) else {
                print("missing \(locale)/\(name)")
                continue
            }
            try rep.representation(using: .png, properties: [:])!.write(to: outDir.appending(path: name))
            if let (copy, size) = scaledCopies[device] {
                try scaled(rep, to: size).representation(using: .png, properties: [:])!
                    .write(to: outDir.appending(path: "\(copy)-\(scene).png"))
            }
            print("framed \(locale)/\(name)")
        }
    }
}

for (alias, source) in aliases {
    let target = root.appending(path: "screenshots").appending(path: alias)
    try fileManager.copyItem(at: root.appending(path: "screenshots").appending(path: source), to: target)
    print("copied \(source) to \(alias)")
}
