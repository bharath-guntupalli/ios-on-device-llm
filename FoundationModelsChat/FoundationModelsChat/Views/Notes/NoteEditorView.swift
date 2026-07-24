//
//  NoteEditorView.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Edits happen directly on the SwiftData model; the store is notified on
//  disappear so Spotlight re-indexes exactly once per editing session.
//

import SwiftData
import SwiftUI

struct NoteEditorView: View {
    @Environment(NotesStore.self) private var store
    @Bindable var note: Note
    @State private var edited = false

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $note.title)
                    .font(.headline)
            }
            Section("Content") {
                TextEditor(text: $note.body)
                    .frame(minHeight: 220)
            }
            if !note.tags.isEmpty {
                Section("Tags") {
                    TagWrap(tags: note.tags)
                }
            }
        }
        .navigationTitle(note.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: note.title) { _, _ in edited = true }
        .onChange(of: note.body) { _, _ in edited = true }
        .onDisappear {
            if edited {
                store.noteDidChange(note)
            }
        }
    }
}

/// Simple flowing tag chips.
struct TagWrap: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }
        }
    }
}
