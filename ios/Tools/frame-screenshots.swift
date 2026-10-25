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
    "ko": [
        "1-appstore": ("WeChat에서도 링크 미리보기", "어떤 링크든 커버와 QR 코드가 담긴 카드로"),
        "3-music": ("QR 코드로 원래 링크 열기", "링크는 복사되어 있어 이미지 다음에 바로 붙여넣기"),
        "4-maps": ("장소, 글, 동영상 모두", "제목, 미리보기 이미지, 사이트 아이콘을 자동으로"),
        "5-history": ("만든 카드는 기록에", "기록은 기기에만 저장됩니다"),
        "6-style": ("다양한 템플릿과 비율", "알맞은 스타일을 자동으로, 직접 고를 수도 있어요"),
        "7-empty": ("링크를 복사하면 시작", "붙여넣거나 아무 앱에서나 OpticShare로 공유"),
    ],
    "ja": [
        "1-appstore": ("WeChat でもリンクをプレビュー", "どんなリンクもカバーと QR コード入りのカードに"),
        "3-music": ("QR コードで元のリンクへ", "リンクはコピー済み。画像のあとに貼り付けるだけ"),
        "4-maps": ("場所も記事も動画も", "タイトル、プレビュー画像、アイコンを自動で取得"),
        "5-history": ("作ったカードは履歴に", "履歴はデバイスだけに保存されます"),
        "6-style": ("テンプレートと比率を選べる", "最適なスタイルを自動で選択、自分で変更も"),
        "7-empty": ("リンクをコピーして始めよう", "貼り付けるか、どのアプリからでも共有"),
    ],
    "ru": [
        "1-appstore": ("Превью ссылок прямо в WeChat", "Любая ссылка — карточка с обложкой и QR-кодом"),
        "3-music": ("QR-код откроет ссылку", "Ссылка уже скопирована — вставьте её после фото"),
        "4-maps": ("Места, статьи, видео", "Заголовок, превью и значок сайта — автоматически"),
        "5-history": ("Все карточки в истории", "История хранится только на устройстве"),
        "6-style": ("Шаблоны и форматы", "Лучший стиль выбирается сам, или выберите свой"),
        "7-empty": ("Скопируйте ссылку", "Вставьте её или поделитесь из любого приложения"),
    ],
    "vi": [
        "1-appstore": ("Xem trước liên kết trên WeChat", "Mọi liên kết thành thẻ có ảnh bìa và mã QR"),
        "3-music": ("Quét QR để mở liên kết", "Liên kết đã được sao chép, dán ngay sau ảnh"),
        "4-maps": ("Địa điểm, bài viết, video", "Tự lấy tiêu đề, ảnh xem trước và biểu tượng"),
        "5-history": ("Mọi thẻ đều có trong Lịch sử", "Lịch sử chỉ lưu trên thiết bị của bạn"),
        "6-style": ("Nhiều mẫu và tỷ lệ", "Tự chọn kiểu phù hợp, hoặc bạn tự đổi"),
        "7-empty": ("Sao chép liên kết để bắt đầu", "Dán vào, hoặc chia sẻ từ bất kỳ ứng dụng nào"),
    ],
    "ar-SA": [
        "1-appstore": ("معاينة الروابط في WeChat", "حوّل أي رابط إلى بطاقة بغلاف ورمز QR"),
        "3-music": ("امسح رمز QR لفتح الرابط", "الرابط منسوخ، الصقه بعد الصورة مباشرة"),
        "4-maps": ("أماكن ومقالات وفيديوهات", "العنوان وصورة المعاينة وأيقونة الموقع تلقائيًا"),
        "5-history": ("كل بطاقاتك في السجل", "يبقى السجل على جهازك فقط"),
        "6-style": ("قوالب ونسب متعددة", "يُختار النمط الأنسب تلقائيًا، أو اختر بنفسك"),
        "7-empty": ("انسخ رابطًا للبدء", "الصقه، أو شاركه مع OpticShare من أي تطبيق"),
    ],
    "fr-FR": [
        "1-appstore": ("Des aperçus dans WeChat", "Chaque lien devient une carte avec couverture et QR"),
        "3-music": ("Scannez le QR pour ouvrir", "Le lien est copié, prêt à coller après l’image"),
        "4-maps": ("Lieux, articles, vidéos", "Titre, aperçu et icône du site, récupérés pour vous"),
        "5-history": ("Toutes vos cartes, gardées", "L’historique reste sur votre appareil"),
        "6-style": ("Modèles et formats", "Le meilleur style est choisi pour vous, ou à votre goût"),
        "7-empty": ("Copiez un lien pour commencer", "Collez-le, ou partagez-le depuis n’importe quelle app"),
    ],
    "de-DE": [
        "1-appstore": ("Linkvorschau direkt in WeChat", "Jeder Link wird zur Karte mit Cover und QR-Code"),
        "3-music": ("QR scannen, Link öffnen", "Der Link ist kopiert – nach dem Bild einfügen"),
        "4-maps": ("Orte, Artikel, Videos", "Titel, Vorschaubild und Symbol – automatisch"),
        "5-history": ("Alle Karten im Verlauf", "Der Verlauf bleibt auf deinem Gerät"),
        "6-style": ("Vorlagen und Formate", "Der passende Stil wird gewählt – oder du wählst selbst"),
        "7-empty": ("Link kopieren und loslegen", "Einfügen oder aus jeder App mit OpticShare teilen"),
    ],
    "es-ES": [
        "1-appstore": ("Vistas previas en WeChat", "Cualquier enlace, en una tarjeta con portada y QR"),
        "3-music": ("Escanea el QR para abrirlo", "El enlace ya está copiado: pégalo tras la imagen"),
        "4-maps": ("Lugares, artículos, vídeos", "Título, vista previa e icono del sitio, al instante"),
        "5-history": ("Todas tus tarjetas, guardadas", "El historial se queda en tu dispositivo"),
        "6-style": ("Plantillas y formatos", "Se elige el mejor estilo, o escoge el tuyo"),
        "7-empty": ("Copia un enlace para empezar", "Pégalo o compártelo desde cualquier app"),
    ],
]
// Locales that reuse another locale's framed screenshots.
let aliases = ["es-MX": "es-ES"]

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

/// CJK locales get explicit fonts so shared Han characters use that language's glyph forms.
func font(_ size: CGFloat, weight: NSFont.Weight, locale: String) -> NSFont {
    let bold = weight == .bold
    let name: String? = switch locale {
    case let l where l.hasPrefix("zh"): bold ? "PingFangSC-Semibold" : "PingFangSC-Regular"
    case "ja": bold ? "HiraginoSans-W6" : "HiraginoSans-W3"
    case "ko": bold ? "AppleSDGothicNeo-Bold" : "AppleSDGothicNeo-Regular"
    default: nil
    }
    if let name, let font = NSFont(name: name, size: size) { return font }
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

let fileManager = FileManager.default
for folder in ["screenshots", "extra"] {
    try? fileManager.removeItem(at: root.appending(path: folder))
}

for (locale, scenes) in captions {
    for (device, layout) in layouts {
        let outDir = root.appending(path: extraDevices.contains(device) ? "extra" : "screenshots").appending(path: locale)
        try fileManager.createDirectory(at: outDir, withIntermediateDirectories: true)
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

for (alias, source) in aliases {
    let target = root.appending(path: "screenshots").appending(path: alias)
    try fileManager.copyItem(at: root.appending(path: "screenshots").appending(path: source), to: target)
    print("copied \(source) to \(alias)")
}
