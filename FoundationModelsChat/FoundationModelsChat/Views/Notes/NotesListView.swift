//
//  NotesListView.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//

import SwiftData
import SwiftUI

struct NotesListView: View {
    @Environment(NotesStore.self) private var store
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]
    @State private var newNote: Note?

    var body: some View {
        Group {
            if notes.isEmpty {
                ContentUnavailableView(
                    "No Notes Yet",
                    systemImage: "note.text",
                    description: Text("Tap + to write your first note. Notes are indexed in Spotlight and become the assistant's knowledge.")
                )
            } else {
                List {
                    ForEach(notes) { note in
                        NavigationLink(value: note.id) {
                            NoteRow(note: note)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            store.delete(notes[index])
                        }
                    }
                }
            }
        }
        .navigationTitle("Notes")
        .navigationDestination(for: UUID.self) { id in
            if let note = notes.first(where: { $0.id == id }) {
                NoteEditorView(note: note)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let note = Note()
                    store.insert(note)
                    newNote = note
                } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
            }
        }
        .navigationDestination(item: $newNote) { note in
            NoteEditorView(note: note)
        }
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.displayTitle)
                .font(.headline)
                .lineLimit(1)
            if !note.body.isEmpty {
                Text(note.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !note.tags.isEmpty {
                Text(note.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
