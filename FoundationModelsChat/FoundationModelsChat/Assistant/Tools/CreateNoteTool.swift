//
//  CreateNoteTool.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  A STATEFUL tool — it mutates the app's store. Creating a note also
//  donates it to Spotlight via NotesStore, so model-created notes join
//  the retrieval corpus like any other.
//

import Foundation
import FoundationModels

struct CreateNoteTool: Tool {
    let name = "createNote"
    let description = "Creates a new note in the user's notes app with a title and body. Use when the user asks to save, note down, or remember something."

    let store: NotesStore

    @Generable
    struct Arguments {
        @Guide(description: "A short title for the note, at most 8 words")
        var title: String

        @Guide(description: "The full note content")
        var body: String
    }

    @MainActor
    func call(arguments: Arguments) async throws -> String {
        let note = Note(title: arguments.title, body: arguments.body)
        store.insert(note)
        return "Created the note \"\(arguments.title)\"."
    }
}
