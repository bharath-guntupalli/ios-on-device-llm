# iOS On-Device LLM Showcase

**Three ways to run a large language model entirely on-device on iOS — compared side by side.**

No server. No API key. Download (or use the built-in) model once, then chat fully offline. This repo is an educational proof-of-concept for iOS developers evaluating on-device inference, and a staging ground for code that will later be lifted into a production app.

## Why this exists

Running LLMs on iPhone hardware has three realistic paths in 2026, each with different trade-offs in model choice, minimum OS, memory behavior, and setup cost. Instead of reading three blog posts, you can open three small, self-contained apps that do the *same thing* (streaming multi-turn chat) with the *same abstraction* (`LLMEngine`), and diff them.

The shared protocol also demonstrates the production pattern this enables: a **fallback chain** that tries the zero-cost system model first and degrades gracefully on older hardware.

## The three approaches

| | [llama.cpp](LlamaCppChat/) | [MLX Swift](MLXChat/) | [Foundation Models](FoundationModelsChat/) |
|---|---|---|---|
| **Status** | ✅ Done (Phase 1) | 🔜 Planned (Phase 2) | 🔜 Planned (Phase 3) |
| Framework | [llama.cpp](https://github.com/ggml-org/llama.cpp) via [llama.swift](https://github.com/mattt/llama.swift) | [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) (MLXLLM) | Apple's built-in [FoundationModels](https://developer.apple.com/documentation/foundationmodels) |
| Model format | GGUF (quantized) | MLX safetensors | Apple's ~3B system model |
| Example model | Llama 3.2 1B Q4_K_M (~0.8 GB) | Llama 3.2 1B 4-bit (~0.7 GB) | built into iOS |
| Weights download | 1 file from Hugging Face | HF repo snapshot (multi-file) | none — ships with the OS |
| Min OS / hardware | broad (Metal or CPU) | device only (Metal required) | iOS 26+, Apple Intelligence devices |
| Simulator support | ✅ (CPU fallback) | ❌ | ⚠️ macOS host must support AI |
| API level you touch | raw C API | high-level Swift | high-level Swift |

## Repository layout

```
├── Packages/LLMEngineKit/     Shared abstraction: LLMEngine protocol, ChatMessage,
│                              EngineAvailability, GenerationMetrics, EngineSelector
├── LlamaCppChat/              Phase 1 — llama.cpp app (complete)
├── MLXChat/                   Phase 2 — MLX Swift app (planned)
└── FoundationModelsChat/      Phase 3 — Foundation Models app (planned)
```

Each app is an independent Xcode project you can open, build, and read on its own — only the small `LLMEngineKit` local package is shared. That keeps every example self-contained (you don't pull MLX's dependency graph to study the llama.cpp app) while guaranteeing all three implement the exact same contract.

## The shared abstraction

Every engine hides behind one protocol ([Packages/LLMEngineKit](Packages/LLMEngineKit/Sources/LLMEngineKit/LLMEngine.swift)):

```swift
public protocol LLMEngine: Sendable {
    static var engineName: String { get }
    static func availability() -> EngineAvailability   // cheap device/OS probe
    func load() async throws                           // config injected at init, not here
    func unload() async
    func generate(_ userMessage: String) async -> AsyncThrowingStream<String, Error>
    func stopGenerating() async
    func resetConversation() async
    var lastMetrics: GenerationMetrics? { get async }  // benchmark instrumentation
}
```

Engine-specific details never leak: llama.cpp's KV-cache management, MLX's Hub snapshots, and Foundation Models' snapshot-to-delta diffing all live behind `generate`'s uniform stream of text deltas.

### Production fallback chain

Because availability is a first-class probe, a production app composes engines in preference order — the whole reason this abstraction exists:

```swift
let engine = EngineSelector.firstAvailable(from: [
    EngineCandidate(name: "Foundation Models",           // free, zero-download…
                    availability: FoundationModelsEngine.availability,
                    make: { FoundationModelsEngine() }),  // …but iOS 26 + AI-eligible only
    EngineCandidate(name: "MLX",                          // Metal-optimized…
                    availability: MLXChatEngine.availability,
                    make: { MLXChatEngine(modelID: "mlx-community/Llama-3.2-1B-Instruct-4bit") }),
    EngineCandidate(name: "llama.cpp",                    // …and the runs-anywhere floor
                    availability: LlamaEngine.availability,
                    make: { LlamaEngine(modelURL: url, family: .llama3) }),
])                                                        // nil → cloud fallback / error UI
```

`EngineAvailability.unavailable(reason:)` carries *why* (e.g. Foundation Models distinguishes "device not eligible" from "Apple Intelligence not enabled" from "model still downloading"), so the UI can tell the user what to do about it.

## Benchmarks (Phase 4 — coming)

Same prompt set, same physical device (iPhone 12, 4 GB — the design floor), cold + warm runs, N=3 median, instrumented via `GenerationMetrics`.

| Engine | Model | Disk | Cold load | TTFT | tok/s | Peak memory | Min OS | Setup complexity |
|---|---|---|---|---|---|---|---|---|
| llama.cpp | Llama 3.2 1B Q4_K_M | 0.8 GB | – | – | – | – | app target | 1 SPM dep + 1-file download |
| MLX | Llama 3.2 1B 4-bit | ~0.7 GB | – | – | – | – | device w/ Metal | 1 SPM dep + Hub snapshot |
| Foundation Models | ~3B system model | 0 | – | – | – | – | iOS 26 + AI | zero |

## Roadmap

- [x] **Phase 1** — llama.cpp chat app, repo structure, `LLMEngineKit` shared protocol
- [ ] **Phase 2** — MLX Swift app (`MLXChatEngine`, Hub snapshot download, Metal cache limits)
- [ ] **Phase 3** — Apple Foundation Models app (availability mapping, snapshot→delta adapter)
- [ ] **Phase 4** — benchmark suite + results table above

## Requirements

- Xcode 26+, iOS 26.5 deployment target (llama.cpp app)
- A physical device for real performance numbers — simulators have no ggml/MLX Metal backend
- For device builds: set your Development Team and enable the **Increased Memory Limit** capability on the App ID

## Comparison
| Approach | Engine Used | Model Location | Storage Needed | Device Support |
| :--- | :--- | :--- | :--- | :--- |
| **1. Apple Foundation Models Framework** | iOS Native System Service | OS System Partition | 0 MB | Apple Intelligence devices only |
| **2. mlx-swift-examples (LLMEval)** | Apple's MLX Framework | App Documents (`.safetensors`) | ~1GB – 2GB per app | All Apple Silicon (iOS 17+) |
| **3. llama.cpp (llama.swift)** | ggml C-Bindings | App Documents (`.gguf`) | ~800MB – 2GB per app | All Apple Silicon (iOS 16+) |

## License

MIT — see [LICENSE](LICENSE).
