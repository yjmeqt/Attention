#!/usr/bin/env swift
// Frames raw simulator screenshots (ios/fastlane/raw) with a caption for App Store Connect.
// Output: ios/fastlane/screenshots/<locale>/<device>-<scene>.png at the required pixel sizes.
// Run from ios/: swift Tools/frame-screenshots.swift
import AppKit

let captions: [String: [String: (title: String, subtitle: String)]] = [
    "zh-Hans": [
        "1-appstore": ("微信里也能看到链接预览", "任何链接一键变成带封面和二维码的卡片"),
        "2-extension": ("在任何 App 里直接分享", "在 Safari 里点分享，选择 OpticShare"),
        "3-music": ("长按二维码，直接打开原链接", "链接已自动复制，发完图片就能粘贴"),
        "4-maps": ("地点、文章、视频都可以", "自动读取标题、预览图和网站图标"),
        "5-history": ("做过的卡片随时找回", "历史记录只保存在你的设备上"),
        "6-style": ("多种模板，多种比例", "自动挑选最合适的样式，也可以自己换"),
        "7-empty": ("复制链接就能开始", "粘贴链接，或从任意 App 分享到 OpticShare"),
    ],
    "en-US": [
        "1-appstore": ("Link previews, right in WeChat", "Turn any link into a card with a cover and QR code"),
        "2-extension": ("Share from any app", "Tap Share in Safari and pick OpticShare"),
        "3-music": ("Scan the QR to open the link", "The link is copied, ready to paste after the image"),
        "4-maps": ("Places, articles, videos", "Title, preview image and site icon, read for you"),
        "5-history": ("Every card, kept in History", "History stays on your device"),
        "6-style": ("Templates and sizes", "The best style is picked for you, or choose your own"),
        "7-empty": ("Copy a link to start", "Paste it, or share it to OpticShare from any app"),
    ],
]

struct Layout {
    let canvas: CGSize
    let shotWidth: CGFloat
    let top: CGFloat
    let titleSize: CGFloat
    let subtitleSize: CGFloat
    let cornerRadius: CGFloat
}

let layouts: [String: Layout] = [
    "iphone": Layout(canvas: CGSize(width: 1320, height: 2868), shotWidth: 1040, top: 560,
                     titleSize: 104, subtitleSize: 52, cornerRadius: 140),
    "ipad": Layout(canvas: CGSize(width: 2064, height: 2752), shotWidth: 1560, top: 540,
                   titleSize: 112, subtitleSize: 56, cornerRadius: 60),
    "duo": Layout(canvas: CGSize(width: 2752, height: 2064), shotWidth: 2200, top: 440,
                  titleSize: 104, subtitleSize: 52, cornerRadius: 70),
]
// App Store Connect has no foldable size class, so these go to fastlane/extra instead of screenshots.
let extraDevices: Set = ["duo"]

let background = NSColor(srgbRed: 0.949, green: 0.929, blue: 0.894, alpha: 1)
let ink = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1)
let secondaryInk = NSColor(srgbRed: 0.33, green: 0.36, blue: 0.33, alpha: 1)
let bezel = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1)

func font(_ size: CGFloat, weight: NSFont.Weight, locale: String) -> NSFont {
    if locale.hasPrefix("zh"), let pingFang = NSFont(name: weight == .bold ? "PingFangSC-Semibold" : "PingFangSC-Regular", size: size) {
        return pingFang
    }
    return .systemFont(ofSize: size, weight: weight)
}

func fitted(_ text: String, size: CGFloat, weight: NSFont.Weight, locale: String, width: CGFloat) -> NSFont {
    var size = size
    while size > 40 {
        let candidate = font(size, weight: weight, locale: locale)
        if (text as NSString).size(withAttributes: [.font: candidate]).width <= width { return candidate }
        size -= 2
    }
    return font(size, weight: weight, locale: locale)
}

func drawCentered(_ text: String, font: NSFont, color: NSColor, y: CGFloat, width: CGFloat, canvasHeight: CGFloat) -> CGFloat {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineBreakMode = .byWordWrapping
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    let bounds = attributed.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                         options: [.usesLineFragmentOrigin, .usesFontLeading])
    let height = ceil(bounds.height)
    attributed.draw(with: CGRect(x: 0, y: canvasHeight - y - height, width: width, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading])
    return height
}

func frame(_ raw: URL, layout: Layout, caption: (title: String, subtitle: String), locale: String, to output: URL) throws {
    guard let shot = NSImage(contentsOf: raw),
          let shotCG = shot.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
    let size = layout.canvas
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext

    background.setFill()
    CGRect(origin: .zero, size: size).fill()

    let margin = size.width * 0.08
    let textWidth = size.width - margin * 2
    cg.saveGState()
    cg.translateBy(x: margin, y: 0)
    let titleFont = fitted(caption.title, size: layout.titleSize, weight: .bold, locale: locale, width: textWidth)
    let subtitleFont = fitted(caption.subtitle, size: layout.subtitleSize, weight: .regular, locale: locale, width: textWidth)
    let titleHeight = drawCentered(caption.title, font: titleFont,
                                   color: ink, y: layout.top * 0.28, width: textWidth, canvasHeight: size.height)
    _ = drawCentered(caption.subtitle, font: subtitleFont,
                     color: secondaryInk, y: layout.top * 0.28 + titleHeight + layout.subtitleSize * 0.5,
                     width: textWidth, canvasHeight: size.height)
    cg.restoreGState()

    let shotHeight = layout.shotWidth * CGFloat(shotCG.height) / CGFloat(shotCG.width)
    let shotRect = CGRect(x: (size.width - layout.shotWidth) / 2, y: size.height - layout.top - shotHeight,
                          width: layout.shotWidth, height: shotHeight)
    let bezelWidth = layout.shotWidth * 0.022
    let bezelRect = shotRect.insetBy(dx: -bezelWidth, dy: -bezelWidth)

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -24), blur: 80, color: NSColor.black.withAlphaComponent(0.22).cgColor)
    bezel.setFill()
    NSBezierPath(roundedRect: bezelRect, xRadius: layout.cornerRadius + bezelWidth, yRadius: layout.cornerRadius + bezelWidth).fill()
    cg.restoreGState()

    cg.saveGState()
    NSBezierPath(roundedRect: shotRect, xRadius: layout.cornerRadius, yRadius: layout.cornerRadius).addClip()
    cg.interpolationQuality = .high
    cg.draw(shotCG, in: shotRect)
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: output)
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "fastlane")
let rawRoot = root.appending(path: "raw")

for (locale, scenes) in captions {
    for (device, layout) in layouts {
        let outDir = root.appending(path: extraDevices.contains(device) ? "extra" : "screenshots").appending(path: locale)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        for (scene, caption) in scenes {
            let name = "\(device)-\(scene).png"
            let raw = rawRoot.appending(path: locale).appending(path: name)
            guard FileManager.default.fileExists(atPath: raw.path) else {
                print("missing \(locale)/\(name)")
                continue
            }
            try frame(raw, layout: layout, caption: caption, locale: locale, to: outDir.appending(path: name))
            print("framed \(locale)/\(name)")
        }
    }
}
