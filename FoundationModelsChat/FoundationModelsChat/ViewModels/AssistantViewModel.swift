//
//  AssistantViewModel.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Bridges the chat UI to NotesAssistant. Token deltas append to the last
//  bubble in place; @Observable handles the redraw coalescing.
//

import Foundation
import Observation

@Observable
final class AssistantViewModel {

    struct DisplayMessage: Identifiable, Equatable, Codable {
        enum Role: String, Codable { case user, assistant }
        var id = UUID()
        let role: Role
        var text: String
    }

    private(set) var messages: [DisplayMessage] = []
    private(set) var isGenerating = false
    var errorMessage: String?
    var infoMessage: String?

    let assistant: NotesAssistant
    private let transcriptStore: TranscriptStore?
    private var generationTask: Task<Void, Never>?

    init(assistant: NotesAssistant, transcriptStore: TranscriptStore? = nil) {
        self.assistant = assistant
        self.transcriptStore = transcriptStore
        // Restore the previous conversation: display messages for the UI,
        // transcript for the model's context.
        if let saved = transcriptStore?.load() {
            messages = saved.messages
            assistant.restore(transcript: saved.transcript)
        }
    }

    /// Persist the conversation (called when the app goes to background).
    func persist() {
        guard !messages.isEmpty else { return }
        transcriptStore?.save(transcript: assistant.transcript, messages: messages)
    }

    func prewarm() {
        assistant.prewarm()
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        errorMessage = nil
        messages.append(DisplayMessage(role: .user, text: trimmed))
        messages.append(DisplayMessage(role: .assistant, text: ""))
        isGenerating = true

        generationTask = Task {
            do {
                for try await delta in assistant.send(trimmed) {
                    messages[messages.count - 1].text += delta
                }
                if assistant.didCondenseLastTurn {
                    infoMessage = "The conversation hit the context window and was condensed."
                }
            } catch {
                handleFailure(error)
            }
            isGenerating = false
        }
    }

    func stop() {
        generationTask?.cancel()
    }

    func newConversation() {
        guard !isGenerating else { return }
        messages = []
        errorMessage = nil
        infoMessage = nil
        assistant.resetConversation()
        transcriptStore?.clear()
    }

    private func handleFailure(_ error: Error) {
        let message = FMErrorPresenter.message(for: error)
        if !message.isEmpty {
            errorMessage = message
        }
        // Drop the empty bubble when nothing streamed before the failure.
        if messages.last?.role == .assistant, messages.last?.text.isEmpty == true {
            messages.removeLast()
        }
    }
}
