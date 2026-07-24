//
//  SearchNotesTool.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Read-only tool: the model decides when it needs the user's notes and
//  generates the query itself (guided generation fills Arguments). The
//  framework runs call(), feeds the output back into the transcript, and
//  the model continues with grounded context.
//

import Foundation
import FoundationModels

struct SearchNotesTool: Tool {
    let name = "searchNotes"
    let description = "Searches the user's saved notes by keyword and returns the best matches with title and content snippet."

    let store: NotesStore

    @Generable
    struct Arguments {
        @Guide(description: "Keywords to search the user's notes for")
        var query: String
    }

    @MainActor
    func call(arguments: Arguments) async throws -> String {
        let hits = store.search(matching: arguments.query, limit: 5)
        guard !hits.isEmpty else {
            return "No notes matched \"\(arguments.query)\"."
        }
        return hits.map { note in
            let snippet = String(note.body.prefix(200))
            return "Note \"\(note.displayTitle)\" (updated \(note.updatedAt.formatted(date: .abbreviated, time: .omitted))): \(snippet)"
        }
        .joined(separator: "\n---\n")
    }
}
