import SwiftUI
import TipKit

/// Points at More once the first-launch share sheet guide has folded into it.
struct GuideTip: Tip {
    @Parameter static var guideFolded: Bool = false

    var title: Text { Text("The guide is in More") }
    var message: Text? { Text("Open it here anytime to watch it again.") }
    var image: Image? { Image(systemName: "ellipsis.circle") }

    var rules: [Rule] {
        #Rule(Self.$guideFolded) { $0 }
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }
}
