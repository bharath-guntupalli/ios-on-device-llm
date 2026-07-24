//
//  NotesAssistant.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  The session owner and orchestrator behind the Assistant tab. Everything
//  the LLMEngine protocol cannot express (tools, transcript surgery,
//  structured output) lives here.
//
//  Prompt-safety posture, reflected in the code shape:
//  - `Instructions` are TRUSTED: composed only from developer constants
//    and user-configured settings. Chat input never reaches instructions.
//  - `Prompt`s are UNTRUSTED: user chat text and note bodies only ever
//    travel as prompt content. The model is trained to prioritize
//    instructions over prompts, which is the injection defense.
//

import Foundation
import FoundationModels
import Observation

@Observable
final class NotesAssistant {

    /// Developer-authored, never interpolated with chat input.
    static let baseInstructions = """
    You are the assistant inside a personal notes app. Be concise and \
    practical. When the user asks about their notes, prefer using the \
    available tools over guessing. Never invent note contents.
    """

    private(set) var isResponding = false
    private let runtime: AssistantRuntime
    private var tools: [any Tool]
    private var session: LanguageModelSession

    /// Options applied to every request; owned by the Settings screen (M6).
    var options = GenerationOptions()

    init(runtime: AssistantRuntime = BaseRuntime(), tools: [any Tool] = []) {
        self.runtime = runtime
        self.tools = tools
        self.session = runtime.makeSession(tools: tools,
                                           instructions: Self.baseInstructions,
                                           transcript: nil)
    }

    /// Warm the model before the first message (call on chat appear).
    func prewarm() {
        session.prewarm()
    }

    var transcript: Transcript {
        session.transcript
    }

    /// Set when the last turn hit the context window and the conversation
    /// was condensed — the UI surfaces this as an informational toast.
    private(set) var didCondenseLastTurn = false

    /// Streams response deltas for one user message. The session keeps the
    /// multi-turn history internally (and reuses its KV cache on append).
    /// On context overflow, the transcript is condensed once and the
    /// message retried transparently.
    func send(_ text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                isResponding = true
                didCondenseLastTurn = false
                defer { isResponding = false }

                do {
                    try await streamOnce(text, into: continuation)
                    continuation.finish()
                } catch let error where FMErrorPresenter.isContextOverflow(error) {
                    do {
                        condenseSession()
                        didCondenseLastTurn = true
                        try await streamOnce(text, into: continuation)
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func streamOnce(_ text: String,
                            into continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        var emitted = ""
        let stream = session.streamResponse(to: text, options: options)
        for try await snapshot in stream {
            if Task.isCancelled { break }
            let full = snapshot.content
            guard full.count > emitted.count else { continue }
            let delta = String(full.dropFirst(emitted.count))
            emitted = full
            continuation.yield(delta)
        }
    }

    /// Context-overflow recovery: keep the instructions entry plus the
    /// most recent turns and rebuild the session from that transcript.
    /// Note the KV-cache trade-off — rewriting the prefix invalidates the
    /// cache, so the next turn pays a full prefill. That is the price of
    /// staying inside the window; appending normally stays cached.
    private func condenseSession() {
        let entries = Array(session.transcript)
        var kept: [Transcript.Entry] = []

        if let first = entries.first, case .instructions = first {
            kept.append(first)
        }
        let recent = entries.suffix(4).filter { entry in
            if case .instructions = entry { return false }
            return true
        }
        kept.append(contentsOf: recent)

        session = runtime.makeSession(tools: tools,
                                      instructions: nil,
                                      transcript: Transcript(entries: kept))
    }

    /// Fresh conversation, same tools and instructions.
    func resetConversation() {
        session = runtime.makeSession(tools: tools,
                                      instructions: Self.baseInstructions,
                                      transcript: nil)
    }

    /// Restore a persisted conversation (Milestone 6).
    func restore(transcript: Transcript) {
        session = runtime.makeSession(tools: tools,
                                      instructions: nil,
                                      transcript: transcript)
    }

    /// Swap the tool set (used when milestones add tools); resets the session.
    func configure(tools: [any Tool]) {
        self.tools = tools
        resetConversation()
    }
}
