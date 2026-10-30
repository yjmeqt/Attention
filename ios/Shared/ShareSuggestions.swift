import UIKit
import Intents

/// Watson saves, Sherlock makes a card and shares it. Attention donates each as a conversation
/// when it does that job, so they show up in the share sheet's suggestions row; tapping one
/// opens the share extension with that conversation as its intent.
enum Assistant: String, CaseIterable {
    case watson, sherlock

    var name: String {
        switch self {
        case .watson: "Watson"
        case .sherlock: "Sherlock"
        }
    }

    /// The assistant the share extension was opened for, if it came from a suggestion.
    init?(intent: INIntent?) {
        guard let id = (intent as? INSendMessageIntent)?.conversationIdentifier else { return nil }
        self.init(rawValue: id)
    }

    func donate() {
        let person = INPerson(personHandle: INPersonHandle(value: rawValue, type: .unknown),
                              nameComponents: nil, displayName: name, image: avatar,
                              contactIdentifier: nil, customIdentifier: rawValue)
        let intent = INSendMessageIntent(recipients: [person], outgoingMessageType: .outgoingMessageText,
                                         content: nil, speakableGroupName: nil, conversationIdentifier: rawValue,
                                         serviceName: nil, sender: nil, attachments: nil)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .outgoing
        interaction.donate(completion: nil)
    }

    /// A stand-in avatar until there's artwork: the job's symbol on a colored circle.
    private var avatar: INImage? {
        let (symbol, color): (String, UIColor) = switch self {
        case .watson: ("book.closed.fill", .systemTeal)
        case .sherlock: ("magnifyingglass", .systemOrange)
        }
        let size = CGSize(width: 240, height: 240)
        let png = UIGraphicsImageRenderer(size: size).pngData { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
            let config = UIImage.SymbolConfiguration(pointSize: 110, weight: .semibold)
            guard let glyph = UIImage(systemName: symbol, withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
            glyph.draw(at: CGPoint(x: (size.width - glyph.size.width) / 2, y: (size.height - glyph.size.height) / 2))
        }
        return INImage(imageData: png)
    }
}
