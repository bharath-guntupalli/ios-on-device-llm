//
//  FoundationModelsEngine.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  LLMEngineKit conformance — the showcase story. Two impedance mismatches
//  this adapter absorbs:
//
//  1. Foundation Models streams CUMULATIVE snapshots ("Hel", "Hello, w",
//     "Hello, world"), while the LLMEngine contract streams DELTAS. The
//     adapter diffs each snapshot against what it already emitted.
//  2. LLMEngine has unload(); Foundation Models has no such concept — the
//     OS owns model residency. unload() here just drops the session.
//
//  The protocol's string-in/string-out shape is where the comparison with
//  llama.cpp/MLX lives. Everything richer (tools, skills, structured
//  output) goes through NotesAssistant instead.
//

import Foundation
import FoundationModels
import LLMEngineKit

actor FoundationModelsEngine: LLMEngine {

    private var session: LanguageModelSession?
    private var stopRequested = false
    public private(set) var lastMetrics: GenerationMetrics?

    nonisolated static var engineName: String { "Apple Foundation Models" }

    nonisolated static func availability() -> EngineAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "Device is not eligible for Apple Intelligence")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Apple Intelligence is not enabled in Settings")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "The on-device model is still downloading")
        case .unavailable(let other):
            return .unavailable(reason: "Unavailable: \(String(describing: other))")
        }
    }

    func load() async throws {
        guard session == nil else { return }
        let session = LanguageModelSession(
            instructions: "You are a concise, helpful assistant. Answer in plain language."
        )
        // Warms the model before the first prompt so time-to-first-token
        // on the opening message is not dominated by model load.
        session.prewarm()
        self.session = session
    }

    func unload() {
        // No model to free — the OS owns it. Dropping the session releases
        // the conversation state.
        session = nil
    }

    func resetConversation() {
        session = LanguageModelSession(
            instructions: "You are a concise, helpful assistant. Answer in plain language."
        )
    }

    func stopGenerating() {
        stopRequested = true
    }

    func generate(_ userMessage: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.run(userMessage: userMessage, continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func run(userMessage: String,
                     continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        guard let session else {
            continuation.finish(throwing: EngineFailure.notLoaded)
            return
        }
        stopRequested = false

        let clock = ContinuousClock()
        let start = clock.now
        var firstTokenAt: ContinuousClock.Instant?
        var emitted = ""

        do {
            let stream = session.streamResponse(to: userMessage)
            for try await snapshot in stream {
                if stopRequested || Task.isCancelled { break }
                let full = snapshot.content
                // Snapshot → delta: emit only the suffix we haven't sent.
                guard full.count > emitted.count else { continue }
                let delta = String(full.dropFirst(emitted.count))
                emitted = full
                if firstTokenAt == nil { firstTokenAt = clock.now }
                continuation.yield(delta)
            }

            let end = clock.now
            lastMetrics = GenerationMetrics(
                timeToFirstToken: firstTokenAt.map { ($0 - start).seconds },
                generationDuration: firstTokenAt.map { (end - $0).seconds },
                tokensGenerated: emitted.split(separator: " ").count, // word-count proxy; exact usage lands with iOS 27's response.usage
                peakMemoryBytes: nil
            )
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    enum EngineFailure: LocalizedError {
        case notLoaded
        var errorDescription: String? { "The engine has not been loaded yet." }
    }
}

private extension Duration {
    nonisolated var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
