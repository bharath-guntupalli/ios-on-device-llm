//
//  ChatViewModel.swift
//  OnDeviceLLM
//
//  Created by Guntupalli, Bharath on 21/07/26.
//
//  MainActor bridge between the chat UI and the LlamaEngine actor. Token
//  deltas from the engine's AsyncThrowingStream are appended to the last
//  message in place; @Observable gives fine-grained invalidation and SwiftUI
//  coalesces redraws, so no manual throttling is needed at 1B-model rates.
//

import Foundation
import Observation

@Observable
@MainActor
final class ChatViewModel {

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    nonisolated struct DisplayMessage: Identifiable, Equatable {
        let id: UUID
        let role: ChatMessage.Role
        var text: String
    }

    let spec: ModelSpec
    private(set) var messages: [DisplayMessage] = []
    private(set) var isGenerating = false
    private(set) var loadState: LoadState = .loading
    var errorMessage: String?

    private let engine: LlamaEngine
    private var generationTask: Task<Void, Never>?

    init(spec: ModelSpec) {
        self.spec = spec
        self.engine = LlamaEngine(config: EngineConfig(nCtx: spec.recommendedContext))
    }

    /// Loads the model into memory. Called once from the view's .task.
    func loadEngine() async {
        loadState = .loading
        do {
            try await engine.load(modelURL: spec.localURL, family: spec.family)
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating, loadState == .ready else { return }

        errorMessage = nil
        messages.append(DisplayMessage(id: UUID(), role: .user, text: trimmed))
        // Empty assistant bubble that fills as tokens stream in.
        messages.append(DisplayMessage(id: UUID(), role: .assistant, text: ""))
        isGenerating = true

        generationTask = Task {
            do {
                for try await delta in await engine.generateResponse(for: trimmed) {
                    messages[messages.count - 1].text += delta
                }
            } catch is CancellationError {
                // User stopped generation — keep whatever streamed so far.
            } catch {
                errorMessage = error.localizedDescription
                // Drop the empty bubble if nothing arrived.
                if messages.last?.role == .assistant, messages.last?.text.isEmpty == true {
                    messages.removeLast()
                }
            }
            isGenerating = false
        }
    }

    /// Stop streaming; the partial response stays in the transcript.
    func stop() {
        Task { await engine.requestStop() }
    }

    /// Clear the transcript and the engine's KV cache; model stays loaded.
    func newConversation() {
        guard !isGenerating else { return }
        messages = []
        errorMessage = nil
        Task { await engine.resetConversation() }
    }

    /// Free the model before navigating away — a 4GB device cannot hold two
    /// models at once, so unload must complete before another engine loads.
    func unloadEngine() async {
        generationTask?.cancel()
        await engine.requestStop()
        await engine.unload()
    }
}
