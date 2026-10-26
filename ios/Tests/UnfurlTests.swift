import Testing
import UIKit
@testable import Attention

/// Live-network smoke tests: unfurl links people commonly share, render a card for each,
/// and write the PNGs to `cards/` in the test's temporary directory for visual review.
@Suite("Unfurling common sites")
struct UnfurlTests {
    nonisolated static let chinese = [
        "https://www.bilibili.com/video/BV1xx411c7mD?spm_id_from=333.1007&vd_source=abc",
        "https://b23.tv/BV1xx411c7mD",
        "https://www.zhihu.com/question/19550225",
        "https://zhuanlan.zhihu.com/p/19550225",
        "https://weibo.com/1195242865",
        "https://www.xiaohongshu.com/explore",
        "https://www.douyin.com",
        "https://baike.baidu.com/item/%E9%95%BF%E5%9F%8E",
        "https://www.douban.com/movie/subject/1292052/",
        "https://movie.douban.com/subject/1292052/",
        "https://sspai.com",
        "https://36kr.com",
        "https://www.jd.com",
        "https://news.qq.com",
        "https://mp.weixin.qq.com",
    ]

    nonisolated static let american = [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=tracking",
        "https://youtu.be/dQw4w9WgXcQ?si=tracking",
        "https://x.com/jack/status/20?s=20",
        "https://github.com/apple/swift",
        "https://www.reddit.com/r/apple/",
        "https://en.wikipedia.org/wiki/Great_Wall_of_China",
        "https://www.nytimes.com",
        "https://medium.com",
        "https://www.instagram.com/instagram/",
        "https://www.tiktok.com/@tiktok",
        "https://www.threads.net/@zuck",
        "https://www.apple.com/iphone/",
        "https://www.amazon.com",
        "https://www.linkedin.com",
        "https://news.ycombinator.com",
    ]

    static let output: URL = {
        let directory = URL.temporaryDirectory.appending(path: "cards", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    @Test(.serialized, arguments: chinese + american)
    func unfurl(_ link: String) async throws {
        let url = try #require(URL(string: link))
        let result = await Unfurler.unfurlWithFallback(url)
        let meta = result.meta
        let size = meta.imagePixelSize.map { "\(Int($0.width))x\(Int($0.height))" } ?? "-"
        let icon = meta.icon.map { "\(Int($0.size.width * $0.scale))" } ?? "-"
        print("UNFURL\t\(result.isFallback ? "FALLBACK" : "ok")\t\(link)\t\(meta.title.prefix(40))\timg \(size)\ticon \(icon)")

        let card = try #require(CardRenderer.render(meta, style: CardStyle()))
        #expect(card.size.width * card.scale == 1080)
        let name = (url.host() ?? "x") + url.path().replacingOccurrences(of: "/", with: "_")
        try card.pngData()?.write(to: Self.output.appending(path: "\(name).png"))
        #expect(!result.isFallback, "No preview for \(link)")
    }
}

@Suite("Card rendering")
struct CardRenderingTests {
    static let sample = LinkMeta(
        url: URL(string: "https://x.com/jack/status/20")!, site: "X",
        title: "just setting up my twttr — 这是一段很长的中文文本，用来测试换行和排版效果。",
        authorName: "jack", authorHandle: "jack")

    @Test(arguments: CardTemplate.allCases, CardAspect.allCases)
    func renders(_ template: CardTemplate, _ aspect: CardAspect) async throws {
        let style = CardStyle(template: template, aspect: aspect)
        let card = try #require(CardRenderer.render(Self.sample, style: style))
        #expect(card.size.width * card.scale == 1080)
        #expect(card.size.height * card.scale == CardView.size(for: Self.sample, style: style).height * 3)
        try card.pngData()?.write(to: UnfurlTests.output.appending(path: "template-\(template)-\(aspect).png"))
    }
}

@Suite("QR codes stay scannable")
struct QRScanTests {
    @Test(arguments: CardAspect.allCases)
    func logoQRDecodes(_ aspect: CardAspect) async throws {
        let logo = UIGraphicsImageRenderer(size: CGSize(width: 180, height: 180)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 180, height: 180))
        }
        let url = "https://www.zhihu.com/question/19550225"
        let meta = LinkMeta(url: URL(string: url)!, site: "zhihu.com", title: "", iconData: logo.pngData())
        let card = try #require(CardRenderer.render(meta, style: CardStyle(aspect: aspect)))
        try card.pngData()?.write(to: UnfurlTests.output.appending(path: "qr-logo-\(aspect).png"))
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let messages = detector.features(in: CIImage(cgImage: try #require(card.cgImage)))
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(messages.contains(url))
    }
}

@Suite("Auto template by image size")
struct ImageShapeTests {
    static func meta(width: Int, height: Int) -> LinkMeta {
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height),
                                            format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
            .image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                UIColor.white.setFill()
                context.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 2))
            }
        return LinkMeta(url: URL(string: "https://example.com/article?utm_source=x")!, site: "example.com",
                        title: "一篇用来测试不同 og:image 尺寸的文章标题，看看排版效果",
                        imageData: image.pngData())
    }

    @Test(arguments: [
        (1200, 630, 9.0 / 16),
        (1280, 720, 9.0 / 16),
        (1024, 1024, 1),
        (1080, 1440, 4.0 / 3),
        (600, 1800, 16.0 / 9),
        (300, 300, nil),
        (600, 600, nil),
        (360, 200, nil),
    ] as [(Int, Int, Double?)])
    func tileKeepsPhotoShape(_ width: Int, _ height: Int, _ expected: Double?) async throws {
        let meta = Self.meta(width: width, height: height)
        #expect(CardTemplate.auto.resolved(for: meta) == .tile)
        let ratio = TileTemplate.imageRatio(meta).map(Double.init)
        #expect((ratio == nil) == (expected == nil))
        if let ratio, let expected { #expect(abs(ratio - expected) < 0.001) }
        let card = try #require(CardRenderer.render(meta, style: CardStyle()))
        #expect(card.size.width == TileTemplate.width)
        try card.pngData()?.write(to: UnfurlTests.output.appending(path: "tile-\(width)x\(height).png"))
    }
}

@Suite("Open Graph parsing")
struct OpenGraphTests {
    @Test func parsesTagsAndEntities() async {
        let html = """
        <head><title>Fallback &amp; title</title>
        <meta content="https://cdn.example.com/a.jpg" property="og:image">
        <meta property='og:title' content='Mark Zuckerberg&#xff08;&#064;zuck&#xff09;&#x2022; Threads'>
        <meta name="twitter:image" content="/b.jpg" />
        </head>
        """
        let tags = OpenGraph.tags(in: html)
        #expect(tags["og:image"] == "https://cdn.example.com/a.jpg")
        #expect(tags["og:title"] == "Mark Zuckerberg（@zuck）• Threads")
        #expect(tags["twitter:image"] == "/b.jpg")
        #expect(OpenGraph.title(in: html) == "Fallback & title")
    }

    @Test func prefersTouchIconThenLargestIcon() async {
        let html = """
        <link rel="icon" href="/16.png" sizes="16x16">
        <link rel="shortcut icon" href="/32.png" sizes="32x32">
        <link rel="apple-touch-icon" href="/touch.png">
        <link rel="icon" href="/logo.svg">
        """
        #expect(OpenGraph.icon(in: html) == "/touch.png")
        #expect(OpenGraph.icon(in: "<link rel=icon href='/a.png'><link rel='icon' href='/b.png' sizes='64x64'>") == "/b.png")
    }
}

@Suite("Share URL cleaning")
struct ShareURLTests {
    @Test(arguments: [
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=abc&t=42", "https://youtu.be/dQw4w9WgXcQ"),
        ("https://youtu.be/dQw4w9WgXcQ?si=abc", "https://youtu.be/dQw4w9WgXcQ"),
        ("https://youtube.com/shorts/abc123?feature=share", "https://youtu.be/abc123"),
        ("https://x.com/jack/status/20?s=20&t=xyz", "https://x.com/jack/status/20"),
        ("https://www.bilibili.com/video/BV1xx411c7mD?spm_id_from=333&vd_source=a&p=2", "https://www.bilibili.com/video/BV1xx411c7mD?p=2"),
        ("https://example.com/a?utm_source=x&utm_medium=y", "https://example.com/a"),
        ("https://www.xiaohongshu.com/explore/1?xsec_token=keep", "https://www.xiaohongshu.com/explore/1?xsec_token=keep"),
    ])
    func cleans(_ input: String, _ expected: String) async {
        #expect(URL(string: input)!.cleanedForSharing.absoluteString == expected)
    }
}
