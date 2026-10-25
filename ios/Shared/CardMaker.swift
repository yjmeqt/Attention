import UIKit
import Observation

@Observable
final class CardMaker {
    var input = ""
    var notice: String?
    var autoSharePending = false
    var style = CardStyle.load() {
        didSet {
            style.save()
            render()
        }
    }
    private(set) var meta: LinkMeta?
    private(set) var card: UIImage?
    private(set) var loading = false
    let history = HistoryStore()

    func make() async {
        guard let url = URL.extract(from: input) else {
            notice = String(localized: "No link found in that text.")
            return
        }
        loading = true
        notice = nil
        let result = await Unfurler.unfurlWithFallback(url)
        loading = false
        show(result.meta)
        history.add(result.meta)
        if result.isFallback { notice = String(localized: "Couldn't load a preview, so this is a basic card.") }
    }

    func show(_ meta: LinkMeta) {
        self.meta = meta
        input = meta.url.absoluteString
        notice = nil
        render()
    }

    private func render() {
        guard let meta else { return }
        card = CardRenderer.render(meta, style: style)
    }
}
