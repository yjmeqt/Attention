import UIKit
import Intents
import os

/// Save and Share, as two conversations in the share sheet's suggestions row. Attention donates
/// each one when it does that job; tapping one opens the share extension with that conversation
/// as its intent.
enum ShareSuggestion: String, CaseIterable {
    case save, share

    var name: String {
        switch self {
        case .save: String(localized: "Save")
        case .share: String(localized: "Share")
        }
    }

    /// The suggestion the share extension was opened from, if any.
    init?(intent: INIntent?) {
        guard let id = (intent as? INSendMessageIntent)?.conversationIdentifier else { return nil }
        self.init(rawValue: id)
    }

    /// Donated as a named group rather than a person: the share sheet matches people against
    /// Contacts, and a group with its own name and image doesn't need a contact behind it.
    func donate() {
        Self.removeOldNames
        let person = INPerson(personHandle: INPersonHandle(value: rawValue, type: .unknown),
                              nameComponents: nil, displayName: name, image: avatar,
                              contactIdentifier: nil, customIdentifier: rawValue)
        let intent = INSendMessageIntent(recipients: [person], outgoingMessageType: .outgoingMessageText,
                                         content: nil, speakableGroupName: INSpeakableString(spokenPhrase: name),
                                         conversationIdentifier: rawValue,
                                         serviceName: nil, sender: nil, attachments: nil)
        intent.setImage(avatar, forParameterNamed: \.speakableGroupName)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .outgoing
        let id = rawValue
        interaction.donate { error in
            if let error {
                Self.log.error("Donating \(id, privacy: .public) failed: \(error, privacy: .public)")
            } else {
                Self.log.notice("Donated \(id, privacy: .public)")
            }
        }
    }

    /// The prototype first donated these as Watson and Sherlock; drops those conversations once per launch.
    private static let removeOldNames: Void = INInteraction.delete(with: ["watson", "sherlock"])

    private static let log = Logger(subsystem: "com.yjmeqt.attn", category: "ShareSuggestions")

    /// A stand-in avatar until there's artwork: the job's symbol on a colored circle.
    private var avatar: INImage? {
        let (symbol, color): (String, UIColor) = switch self {
        case .save: ("tray.and.arrow.down.fill", .systemTeal)
        case .share: ("square.and.arrow.up.fill", .systemOrange)
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
