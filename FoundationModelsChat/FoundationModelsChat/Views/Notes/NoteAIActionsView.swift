//
//  NoteAIActionsView.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  The guided-generation showcase: a card whose fields fill in live as
//  the model streams PartiallyGenerated snapshots of NoteSummary.
//

import SwiftUI

struct NoteAIActionsView: View {
    @Environment(NotesStore.self) private var store
    @Bindable var note: Note
    @State private var viewModel = NoteAIActionsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI Summary", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                if viewModel.isGenerating {
                    Button("Cancel") { viewModel.cancel() }
                        .font(.caption)
                } else {
                    Button(viewModel.partial == nil ? "Generate" : "Regenerate") {
                        viewModel.generateSummary(for: note)
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .disabled(note.body.count < 20)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let partial = viewModel.partial {
                summaryCard(partial)
            } else if !viewModel.isGenerating {
                Text("Generates a better title, a short summary, and action items from the note. Fields appear live as the model writes them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.isGenerating {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func summaryCard(_ partial: NoteSummary.PartiallyGenerated) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = partial.suggestedTitle {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Suggested title")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                    }
                    Spacer()
                    Button("Apply") {
                        note.title = title
                        store.noteDidChange(note)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }

            if let summary = partial.summary {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Summary")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.subheadline)
                }
            }

            if let items = partial.actionItems, !items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Action items")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Label(item, systemImage: "checkmark.circle")
                            .font(.subheadline)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }
}
