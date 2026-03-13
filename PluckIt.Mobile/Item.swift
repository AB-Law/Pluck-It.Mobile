//
//  Item.swift
//  PluckIt.Mobile
//
//  Created by Akshay B on 13/03/26.
//

import Foundation
import SwiftData

@Model
/// Local draft queue row while upload and auth requests are being processed.
/// This is intentionally lightweight and separate from the API-facing wardrobe model.
final class DraftQueueItem {
    @Attribute(.unique) var localId: String
    var draftId: String?
    var status: String
    var createdAt: Date
    var lastUpdatedAt: Date?

    init(localId: String = UUID().uuidString, draftId: String? = nil, status: String = "queued") {
        self.localId = localId
        self.draftId = draftId
        self.status = status
        self.createdAt = Date()
        self.lastUpdatedAt = nil
    }
}
