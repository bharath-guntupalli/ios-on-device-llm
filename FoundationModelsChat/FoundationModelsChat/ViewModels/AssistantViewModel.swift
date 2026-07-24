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

    struct DisplayMessage: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
    }

    private(set) var messages: [DisplayMessage] = []
    private(set) var isGenerating = false
    var errorMessage: String?

    let assistant: NotesAssistant
    private var generationTask: Task<Void, Never>?

    init(assistant: NotesAssistant) {
        self.assistant = assistant
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
        assistant.resetConversation()
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
