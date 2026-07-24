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
    @Environment(AvailabilityGate.self) private var gate
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
            if case .available = gate.state {
                Section {
                    NoteAIActionsView(note: note)
                }
            }
        }
        .navigationTitle(note.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: note.title) { _, _ in edited = true }
        .onChange(of: note.body) { _, _ in edited = true }
        .onDisappear {
            guard edited else { return }
            store.noteDidChange(note)
            autoTag()
        }
    }

    /// Fire-and-forget auto-tagging with the .contentTagging use case.
    /// Runs after the editing session ends; merges non-destructively.
    private func autoTag() {
        let noteToTag = note
        let currentStore = store
        Task {
            let fresh = await TaggingService().tags(for: noteToTag.body)
            guard !fresh.isEmpty else { return }
            let merged = Array(Set(noteToTag.tags).union(fresh)).sorted()
            if merged != noteToTag.tags.sorted() {
                noteToTag.tags = merged
                currentStore.noteDidChange(noteToTag)
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
