import SwiftUI
import TipKit

/// Points out the long-press menu once the library has a few links in it.
struct LongPressTip: Tip {
    @Parameter static var itemCount: Int = 0

    var title: Text { Text("Touch and hold a link") }
    var message: Text? { Text("Tag it, archive it, move it to Private, or delete it.") }
    var image: Image? { Image(systemName: "hand.point.up.left") }

    var rules: [Rule] {
        #Rule(Self.$itemCount) { $0 >= 3 }
    }

    var options: [any TipOption] {
        MaxDisplayCount(3)
    }
}
