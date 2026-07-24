//
//  SpotlightIndexer.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Donates every note to the Core Spotlight index. Two reasons:
//  1. Notes become searchable from system Spotlight today.
//  2. This index is the retrieval corpus for Phase B's SpotlightSearchTool
//     RAG mode — the OS builds on-device semantic matching over donated
//     items, so indexing well now is what makes "ask my notes" work later.
//

import CoreSpotlight
import Foundation

nonisolated struct SpotlightIndexer {

    static let domainIdentifier = "BharathGuntupalli.FoundationModelsChat.notes"

    /// Index (or re-index) one note. Title, body, and tags are the fields
    /// the model will later receive as grounding context.
    func index(id: UUID, title: String, body: String, tags: [String]) {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = title
        attributes.textContent = body
        attributes.keywords = tags

        let item = CSSearchableItem(
            uniqueIdentifier: id.uuidString,
            domainIdentifier: Self.domainIdentifier,
            attributeSet: attributes
        )

        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                print("Spotlight indexing failed: \(error.localizedDescription)")
            }
        }
    }

    func remove(id: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id.uuidString]) { error in
            if let error {
                print("Spotlight removal failed: \(error.localizedDescription)")
            }
        }
    }
}
