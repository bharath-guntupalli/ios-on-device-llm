//
//  NoteAIActionsViewModel.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Streams a structured NoteSummary. Each iteration delivers the WHOLE
//  object generated so far (PartiallyGenerated snapshot), so assigning it
//  to `partial` progressively fills the card in the UI.
//

import Foundation
import FoundationModels
import Observation

@Observable
final class NoteAIActionsViewModel {

    private(set) var partial: NoteSummary.PartiallyGenerated?
    private(set) var isGenerating = false
    var errorMessage: String?

    private var task: Task<Void, Never>?

    func generateSummary(for note: Note) {
        guard !isGenerating else { return }
        isGenerating = true
        errorMessage = nil
        partial = nil

        task = Task {
            // A fresh single-purpose session per run: summary generation
            // shouldn't inherit or pollute chat history.
            let session = LanguageModelSession(
                instructions: "You summarize personal notes faithfully. Never invent facts that are not in the note."
            )
            do {
                let stream = session.streamResponse(
                    to: "Summarize this note:\n\nTitle: \(note.displayTitle)\n\n\(note.body)",
                    generating: NoteSummary.self
                )
                for try await snapshot in stream {
                    if Task.isCancelled { break }
                    partial = snapshot.content
                }
            } catch {
                let message = FMErrorPresenter.message(for: error)
                if !message.isEmpty { errorMessage = message }
            }
            isGenerating = false
        }
    }

    func cancel() {
        task?.cancel()
        isGenerating = false
    }
}
