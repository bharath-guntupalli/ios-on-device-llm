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

    /// Streams response deltas for one user message. The session keeps the
    /// multi-turn history internally (and reuses its KV cache on append).
    func send(_ text: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                isResponding = true
                defer { isResponding = false }

                var emitted = ""
                do {
                    let stream = session.streamResponse(to: text, options: options)
                    for try await snapshot in stream {
                        if Task.isCancelled { break }
                        let full = snapshot.content
                        guard full.count > emitted.count else { continue }
                        let delta = String(full.dropFirst(emitted.count))
                        emitted = full
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
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
