import Foundation
import SwiftData

/// A list this person shared, kept so they can share its card again or take it down. Synced through
/// CloudKit with the library, so a list shared on one device can be revoked on another.
/// The delete token is the only proof of ownership the server accepts, and it lives only here,
/// in the person's private iCloud database.
@Model
final class SharedListRecord {
    /// The server's ID: the list is at `https://attentioncard.com/l/<listID>`.
    var listID = ""
    var title = ""
    var itemCount = 0
    var createdAt = Date.now
    var deleteToken = ""

    init(listID: String, title: String, itemCount: Int, deleteToken: String, createdAt: Date = .now) {
        self.listID = listID
        self.title = title
        self.itemCount = itemCount
        self.deleteToken = deleteToken
        self.createdAt = createdAt
    }
}

extension SharedListRecord {
    var url: URL { URL(string: "https://attentioncard.com/l/\(listID)")! }
}
