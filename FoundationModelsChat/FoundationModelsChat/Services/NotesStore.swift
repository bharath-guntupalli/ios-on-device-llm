//
//  NotesStore.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  CRUD facade over the SwiftData context. Every mutation goes through
//  here so the Spotlight index can never drift out of sync with the store
//  — the assistant's tools (Milestone 5) and the Phase B RAG mode both
//  depend on that invariant.
//

import Foundation
import SwiftData

@Observable
final class NotesStore {

    private let context: ModelContext
    private let indexer = SpotlightIndexer()

    init(context: ModelContext) {
        self.context = context
    }

    func insert(_ note: Note) {
        context.insert(note)
        persistAndIndex(note)
    }

    /// Call after editing an existing note's fields.
    func noteDidChange(_ note: Note) {
        note.updatedAt = .now
        persistAndIndex(note)
    }

    func delete(_ note: Note) {
        indexer.remove(id: note.id)
        context.delete(note)
        try? context.save()
    }

    /// Keyword search used by the assistant's SearchNotesTool (Milestone 5).
    func search(matching query: String, limit: Int = 5) -> [Note] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let predicate = #Predicate<Note> { note in
            note.title.localizedStandardContains(needle)
                || note.body.localizedStandardContains(needle)
        }
        var descriptor = FetchDescriptor<Note>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    func allNotes() -> [Note] {
        let descriptor = FetchDescriptor<Note>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func persistAndIndex(_ note: Note) {
        try? context.save()
        indexer.index(id: note.id, title: note.displayTitle, body: note.body, tags: note.tags)
    }
}
