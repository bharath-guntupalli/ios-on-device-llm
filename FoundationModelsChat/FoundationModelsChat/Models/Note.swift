//
//  Note.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  The core SwiftData entity. `id` is our own stable UUID and doubles as
//  the Core Spotlight uniqueIdentifier — chosen deliberately over
//  persistentModelID so the Spotlight index survives store migrations.
//

import Foundation
import SwiftData

@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var title: String
    var body: String
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    /// Reserved for the Phase B vision feature (attach a photo, ask about it).
    @Attribute(.externalStorage) var imageData: Data?

    init(id: UUID = UUID(),
         title: String = "",
         body: String = "",
         tags: [String] = [],
         createdAt: Date = .now,
         updatedAt: Date = .now,
         imageData: Data? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imageData = imageData
    }

    /// Display title that never renders as an empty row.
    var displayTitle: String {
        title.isEmpty ? "Untitled" : title
    }
}
