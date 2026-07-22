//
//  LLMEngine.swift
//  LLMEngineKit
//
//  Created by Guntupalli, Bharath on 22/07/26.
//
//  The engine abstraction every showcase app conforms to. Design notes:
//
//  - `generate` is `async` so an actor's isolated method satisfies it
//    directly (an actor-isolated synchronous method cannot witness a
//    non-async protocol requirement).
//  - Engine-specific configuration (model URL, model ID, context size…)
//    is injected at the concrete engine's init, keeping `load()` bare:
//    Foundation Models needs no config, MLX wants a Hub model ID, and
//    llama.cpp wants a file URL + prompt-template family.
//  - The stream contract is DELTAS, not cumulative snapshots. Backends
//    that stream snapshots (Apple Foundation Models) must diff against
//    the previously emitted prefix in their adapter.
//

/// A conversational on-device LLM engine. Conformers own their conversation
/// state; `generate` appends one user turn and streams the assistant's reply.
public protocol LLMEngine: Sendable {

    /// Human-readable engine name for UI and benchmarks (e.g. "llama.cpp").
    static var engineName: String { get }

    /// Cheap, synchronous device/OS support probe used by fallback chains.
    /// Must never load the model or allocate significant memory.
    static func availability() -> EngineAvailability

    /// Load weights / create a session. Safe to call when already loaded.
    func load() async throws

    /// Free the model and all inference state. Must be awaited before
    /// loading a different engine on memory-constrained devices.
    func unload() async

    /// Streams UTF-8-safe response deltas for one user message.
    func generate(_ userMessage: String) async -> AsyncThrowingStream<String, Error>

    /// Stop after the in-flight token; partial output stays in history.
    func stopGenerating() async

    /// Clear conversation state; the model stays loaded.
    func resetConversation() async

    /// Metrics for the most recently completed generation, if instrumented.
    var lastMetrics: GenerationMetrics? { get async }
}

public extension LLMEngine {
    /// Engines are not required to instrument themselves.
    var lastMetrics: GenerationMetrics? { nil }
}
