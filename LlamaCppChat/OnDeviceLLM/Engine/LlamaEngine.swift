//
//  LlamaEngine.swift
//  OnDeviceLLM
//
//  Created by Guntupalli, Bharath on 21/07/26.
//
//  A Swift actor over the raw llama.cpp C API (the LlamaSwift package is a
//  thin re-export of the C headers — there is no Swift wrapper).
//
//  Memory model, sized for a 4GB iPhone 12:
//  - Weights (Q4_K_M 1B ≈ 0.8GB) are offloaded to Metal (n_gpu_layers = 99).
//  - n_ctx is capped at 2048 and maxNewTokens reserved inside it, so the KV
//    cache stays small and multi-turn chats can't overrun the context.
//  - os_proc_available_memory() is checked before load and periodically
//    during generation; we stop cleanly instead of getting jetsammed.
//
//  KV-cache strategy for multi-turn chat:
//  - The token ids resident in the KV cache are mirrored in `cachedTokens`.
//  - Each new user turn appends only a rendered *suffix* (close previous
//    assistant turn + new user turn + open assistant header) behind the
//    cache, so earlier turns are never re-decoded — second-turn prefill is
//    near-instant.
//  - When the budget would overflow, the oldest user/assistant pair is
//    dropped from history, the KV cache is cleared, and the trimmed
//    conversation is re-prefilled from scratch.
//

import Foundation
import LLMEngineKit
import LlamaSwift
import os

// MARK: - Configuration

nonisolated struct EngineConfig: Sendable {
    var nCtx: Int32 = 2048
    var nBatch: Int32 = 512
    var nThreads: Int32 = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 2))
    /// Layers offloaded to Metal. The simulator has no Metal backend for
    /// ggml — force CPU there so the app still runs (slowly) for UI testing.
    #if targetEnvironment(simulator)
    var nGpuLayers: Int32 = 0
    #else
    var nGpuLayers: Int32 = 99
    #endif
    /// Generation budget reserved inside n_ctx on every turn.
    var maxNewTokens: Int32 = 512
    var temperature: Float = 0.7
    var topK: Int32 = 40
    var topP: Float = 0.9
    /// Stop generating when the process gets this close to its memory limit.
    var minFreeMemoryBytes: Int = 300 * 1024 * 1024
}

// MARK: - Errors

nonisolated enum EngineError: LocalizedError {
    case modelLoadFailed(String)
    case contextCreationFailed
    case tokenizationFailed
    case decodeFailed(code: Int32)
    case contextOverflow
    case lowMemory
    case notLoaded
    case busy

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let detail):
            return "The model could not be loaded (\(detail)). The file may be corrupt — try deleting and re-downloading it."
        case .contextCreationFailed:
            return "Could not create an inference context. Try closing other apps to free memory."
        case .tokenizationFailed:
            return "The prompt could not be tokenized."
        case .decodeFailed(let code):
            return "Inference failed (llama_decode returned \(code))."
        case .contextOverflow:
            return "The message is too long for the model's context window."
        case .lowMemory:
            return "Not enough free memory to run the model. Close other apps and try again."
        case .notLoaded:
            return "No model is loaded."
        case .busy:
            return "A response is already being generated."
        }
    }
}

// MARK: - Engine

actor LlamaEngine {

    // llama.cpp opaque handles. `llama_model`, `llama_context`, `llama_vocab`
    // and `llama_memory_t` are incomplete C types → OpaquePointer in Swift.
    private var model: OpaquePointer?
    private var ctx: OpaquePointer?
    private var vocab: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    private var batch: llama_batch?

    private let config: EngineConfig
    private var template: ChatTemplate?

    /// Conversation turns (user/assistant only; the system prompt lives in
    /// the template and is rendered separately).
    private var history: [ChatMessage] = []
    /// Mirror of the tokens actually resident in the KV cache. Its count is
    /// the next decode position (`n_past`).
    private var cachedTokens: [llama_token] = []

    private var isGenerating = false
    private var stopRequested = false

    /// llama_backend_init must run exactly once per process; a `static let`
    /// initializer is lazy and thread-safe.
    private static let backendInitialized: Bool = {
        llama_backend_init()
        return true
    }()

    /// Engine-specific configuration is injected here (not in `load()`) so
    /// the type can satisfy `LLMEngine`'s parameterless `load()` — each
    /// engine family wants different knobs, and the protocol stays agnostic.
    private let modelURL: URL
    private let family: ChatTemplateFamily

    init(config: EngineConfig = EngineConfig(),
         modelURL: URL,
         family: ChatTemplateFamily) {
        self.config = config
        self.modelURL = modelURL
        self.family = family
    }

    deinit {
        // Actor deinit has exclusive access to stored state; free C memory.
        if let sampler { llama_sampler_free(sampler) }
        if let batch { llama_batch_free(batch) }
        if let ctx { llama_free(ctx) }
        if let model { llama_model_free(model) }
    }

    // MARK: Lifecycle

    var isLoaded: Bool { ctx != nil }

    /// Loads the GGUF model from disk with Metal offload and prepares the
    /// context, sampler chain, and reusable batch.
    func load() throws {
        guard !isLoaded else { return }
        _ = Self.backendInitialized

        // OOM preflight: require the model size plus headroom before even
        // touching llama.cpp. os_proc_available_memory() reports the distance
        // to the jetsam limit (0 on the simulator → skip the check there).
        let fileSize = (try? FileManager.default
            .attributesOfItem(atPath: modelURL.path)[.size] as? Int64) ?? 0
        let available = os_proc_available_memory()
        if available > 0, available < Int(fileSize) + 500 * 1024 * 1024 {
            throw EngineError.lowMemory
        }

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = config.nGpuLayers

        guard let loadedModel = llama_model_load_from_file(modelURL.path, modelParams) else {
            throw EngineError.modelLoadFailed(modelURL.lastPathComponent)
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(config.nCtx)
        ctxParams.n_batch = UInt32(config.nBatch)
        ctxParams.n_threads = config.nThreads
        ctxParams.n_threads_batch = config.nThreads

        guard let context = llama_init_from_model(loadedModel, ctxParams) else {
            llama_model_free(loadedModel)
            throw EngineError.contextCreationFailed
        }

        // Standard sampler chain, in the order recommended by llama.h:
        // top-k → top-p → temperature → final distribution sample.
        // llama_sampler_sample() both samples and accepts the token.
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(config.topK))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(config.topP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(config.temperature))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: .min ... .max)))

        model = loadedModel
        ctx = context
        vocab = llama_model_get_vocab(loadedModel)
        sampler = chain
        batch = llama_batch_init(config.nBatch, 0, 1)
        template = ChatTemplate(family: family)
        history = []
        cachedTokens = []
    }

    /// Frees the model and all inference state. Call before loading a
    /// different model — a 4GB device cannot hold two models at once.
    func unload() {
        if let sampler { llama_sampler_free(sampler) }
        if let batch { llama_batch_free(batch) }
        if let ctx { llama_free(ctx) }
        if let model { llama_model_free(model) }
        sampler = nil
        batch = nil
        ctx = nil
        model = nil
        vocab = nil
        template = nil
        history = []
        cachedTokens = []
    }

    /// Clears the conversation and the KV cache; the model stays loaded.
    func resetConversation() {
        history = []
        cachedTokens = []
        if let ctx {
            llama_memory_clear(llama_get_memory(ctx), true)
        }
    }

    /// Ask the current generation to stop after the in-flight token.
    func requestStop() {
        stopRequested = true
    }

    // MARK: Generation

    /// Streams the assistant's response for one user message. Token pieces
    /// are yielded as UTF-8-safe string fragments as soon as they decode.
    func generateResponse(for userMessage: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            // Consumer walked away (view dismissed, stop button, task
            // cancelled) → halt decoding within one token.
            continuation.onTermination = { _ in
                Task { await self.requestStop() }
            }
            Task {
                await self.run(userMessage: userMessage, continuation: continuation)
            }
        }
    }

    private func run(userMessage: String,
                     continuation: AsyncThrowingStream<String, Error>.Continuation) async {
        guard let ctx, let vocab, let template else {
            continuation.finish(throwing: EngineError.notLoaded)
            return
        }
        guard !isGenerating else {
            continuation.finish(throwing: EngineError.busy)
            return
        }
        isGenerating = true
        stopRequested = false
        defer { isGenerating = false }

        do {
            // 1. Render only the *new* text. Past turns are never re-rendered
            //    while the cache is valid: retokenizing sampled output is not
            //    guaranteed to reproduce the token ids that were decoded, and
            //    any mismatch would silently corrupt the cache's meaning.
            let suffixText = cachedTokens.isEmpty
                ? template.renderFull(history: history + [ChatMessage(role: .user, content: userMessage)])
                : template.renderSuffix(newUserMessage: userMessage)
            history.append(ChatMessage(role: .user, content: userMessage))

            // Special tokens live in the rendered text: parse them, and never
            // let llama add its own BOS on top (add_special = false).
            var suffixTokens = try tokenize(suffixText)

            // 2. Context budget: keep [cache + new prompt + generation
            //    reserve] inside n_ctx by dropping the oldest exchange and
            //    rebuilding the cache from the trimmed history.
            while cachedTokens.count + suffixTokens.count + Int(config.maxNewTokens) > Int(config.nCtx) {
                // history currently ends with the new user message.
                guard history.count > 3 else { throw EngineError.contextOverflow }
                history.removeFirst(2) // oldest user + assistant pair
                llama_memory_clear(llama_get_memory(ctx), true)
                cachedTokens = []
                suffixTokens = try tokenize(template.renderFull(history: history))
            }

            // 3. Prefill the prompt suffix in nBatch-sized chunks.
            var index = 0
            while index < suffixTokens.count {
                try checkAbort()
                let chunk = Array(suffixTokens[index ..< min(index + Int(config.nBatch), suffixTokens.count)])
                let isLastChunk = index + chunk.count == suffixTokens.count
                try decode(tokens: chunk, logitsForLastToken: isLastChunk)
                cachedTokens.append(contentsOf: chunk)
                index += chunk.count
                await Task.yield() // let requestStop() interleave
            }

            // 4. Token-by-token generation.
            guard let sampler else { throw EngineError.notLoaded }
            var pieceBuffer = [CChar](repeating: 0, count: 256)
            var pendingUTF8: [UInt8] = []
            var assistantText = ""

            for step in 0 ..< Int(config.maxNewTokens) {
                try checkAbort()

                // Periodic OOM guard: stop cleanly rather than risk jetsam.
                if step % 32 == 0 {
                    let free = os_proc_available_memory()
                    if free > 0, free < config.minFreeMemoryBytes { break }
                }

                let token = llama_sampler_sample(sampler, ctx, -1)

                // End-of-generation (<|eot_id|>, <|im_end|>, …). The EOG
                // token is *not* decoded into the cache — renderSuffix
                // re-inserts the closing marker verbatim on the next turn.
                if llama_vocab_is_eog(vocab, token) { break }

                // Token pieces are raw bytes; one emoji/CJK character can
                // span several tokens, so buffer and emit only valid UTF-8.
                let pieceLength = llama_token_to_piece(vocab, token, &pieceBuffer,
                                                       Int32(pieceBuffer.count), 0, true)
                if pieceLength > 0 {
                    pieceBuffer[0 ..< Int(pieceLength)].withUnsafeBufferPointer { buf in
                        buf.baseAddress!.withMemoryRebound(to: UInt8.self, capacity: Int(pieceLength)) {
                            pendingUTF8.append(contentsOf: UnsafeBufferPointer(start: $0, count: Int(pieceLength)))
                        }
                    }
                    if let text = Self.drainValidUTF8Prefix(from: &pendingUTF8), !text.isEmpty {
                        assistantText += text
                        continuation.yield(text)
                    }
                }

                // Hard stop at the window edge; the reserve normally
                // prevents this, but never decode past n_ctx.
                if cachedTokens.count + 1 >= Int(config.nCtx) { break }

                try decode(tokens: [token], logitsForLastToken: true)
                cachedTokens.append(token)
                await Task.yield()
            }

            // 5. Record the finished turn. Any bytes still pending are an
            //    incomplete UTF-8 sequence — drop them.
            history.append(ChatMessage(role: .assistant, content: assistantText))
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    // MARK: Helpers

    private func checkAbort() throws {
        if stopRequested || Task.isCancelled {
            throw CancellationError()
        }
    }

    private func tokenize(_ text: String) throws -> [llama_token] {
        guard let vocab else { throw EngineError.notLoaded }
        let byteCount = text.utf8.count
        // Token count never exceeds byte count; +16 covers special tokens.
        var capacity = byteCount + 16
        var tokens = [llama_token](repeating: 0, count: capacity)
        var written = llama_tokenize(vocab, text, Int32(byteCount),
                                     &tokens, Int32(capacity),
                                     false /* add_special */, true /* parse_special */)
        if written < 0 { // buffer too small; llama reports the needed size
            capacity = Int(-written)
            tokens = [llama_token](repeating: 0, count: capacity)
            written = llama_tokenize(vocab, text, Int32(byteCount),
                                     &tokens, Int32(capacity), false, true)
        }
        guard written > 0 else { throw EngineError.tokenizationFailed }
        return Array(tokens.prefix(Int(written)))
    }

    /// Decodes up to nBatch tokens starting at the current cache position.
    /// Logits are requested only for the final token (we only sample there).
    private func decode(tokens: [llama_token], logitsForLastToken: Bool) throws {
        guard let ctx, var batch else { throw EngineError.notLoaded }
        precondition(tokens.count <= Int(config.nBatch))

        let basePosition = llama_pos(cachedTokens.count)
        batch.n_tokens = Int32(tokens.count)
        for i in 0 ..< tokens.count {
            batch.token[i] = tokens[i]
            batch.pos[i] = basePosition + llama_pos(i)
            batch.n_seq_id[i] = 1
            batch.seq_id[i]?[0] = 0
            batch.logits[i] = 0
        }
        if logitsForLastToken {
            batch.logits[tokens.count - 1] = 1
        }

        let status = llama_decode(ctx, batch)
        guard status == 0 else { throw EngineError.decodeFailed(code: status) }
    }

    /// Removes and returns the longest valid-UTF-8 prefix of `pending`,
    /// leaving at most one incomplete trailing multibyte sequence behind.
    private static func drainValidUTF8Prefix(from pending: inout [UInt8]) -> String? {
        guard !pending.isEmpty else { return nil }

        var end = pending.count
        // A UTF-8 sequence is at most 4 bytes; scan back over trailing
        // continuation bytes (10xxxxxx) to the last lead byte.
        var i = pending.count - 1
        var stepsBack = 0
        while i >= 0, stepsBack < 4 {
            let byte = pending[i]
            if byte & 0b1100_0000 != 0b1000_0000 { // lead byte or ASCII
                let sequenceLength: Int
                switch byte {
                case ..<0x80:                        sequenceLength = 1
                case _ where byte & 0b1110_0000 == 0b1100_0000: sequenceLength = 2
                case _ where byte & 0b1111_0000 == 0b1110_0000: sequenceLength = 3
                case _ where byte & 0b1111_1000 == 0b1111_0000: sequenceLength = 4
                default:                             sequenceLength = 1 // invalid → emit
                }
                if pending.count - i < sequenceLength {
                    end = i // trailing sequence incomplete — hold it back
                }
                break
            }
            i -= 1
            stepsBack += 1
        }

        guard end > 0 else { return nil }
        let chunk = pending[0 ..< end]
        let text = String(decoding: chunk, as: UTF8.self)
        pending.removeFirst(end)
        return text
    }
}

// MARK: - LLMEngine conformance

/// Adapts the actor to the showcase-wide engine abstraction. The isolated
/// synchronous methods satisfy the protocol's `async` requirements directly.
extension LlamaEngine: LLMEngine {
    static var engineName: String { "llama.cpp" }

    /// GGUF inference runs everywhere: Metal on device, CPU fallback on the
    /// simulator (EngineConfig already zeroes nGpuLayers there).
    static func availability() -> EngineAvailability { .available }

    func generate(_ userMessage: String) -> AsyncThrowingStream<String, Error> {
        generateResponse(for: userMessage)
    }

    func stopGenerating() {
        requestStop()
    }
}
