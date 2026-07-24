# iOS On-Device LLM Showcase

Three ways to run a language model entirely on an iPhone, built as small apps you can read side by side. No server and no API key: you download a model once (or use the one built into iOS) and chat offline.

It is a learning project first. Each app is kept small on purpose, and the parts that hold up will get pulled into a real app later.

## Why three apps

There are three realistic ways to run an LLM on iPhone hardware right now, and they disagree on almost everything: which model you can run, which iOS version you need, how much storage it costs, and how much setup it takes. Instead of describing the differences, this repo builds all three as the same app (streaming multi-turn chat) behind the same Swift protocol (`LLMEngine`), so you can open them next to each other and compare.

The shared protocol pays off in production too. You can chain the engines so the app tries the free built-in model first and falls back to the others when the hardware cannot run it.

## Comparison

| Approach | Engine Used | Model Location | Storage Needed | Device Support |
| :--- | :--- | :--- | :--- | :--- |
| **1. Apple Foundation Models Framework** | iOS Native System Service | OS System Partition | 0 MB | Apple Intelligence devices only |
| **2. mlx-swift-examples (LLMEval)** | Apple's MLX Framework | App Documents (`.safetensors`) | ~1 to 2 GB per app | All Apple Silicon (iOS 17+) |
| **3. llama.cpp (llama.swift)** | ggml C-Bindings | App Documents (`.gguf`) | ~800 MB to 2 GB per app | All Apple Silicon (iOS 16+) |

The llama.cpp app is complete (Phase 1) and the Foundation Models app is in progress (Phase 2, a smart-notes assistant with its iOS 26 surface built and an iOS 27 beta plan written). MLX comes after. Each approach has its own project and README: [LlamaCppChat](LlamaCppChat/), [FoundationModelsChat](FoundationModelsChat/), and [MLXChat](MLXChat/).

## Repository layout

```
├── Packages/LLMEngineKit/     Shared code: LLMEngine protocol, ChatMessage,
│                              EngineAvailability, GenerationMetrics, EngineSelector
├── LlamaCppChat/              Phase 1: llama.cpp app (built)
├── FoundationModelsChat/      Phase 2: Foundation Models smart-notes app (in progress)
└── MLXChat/                   Phase 3: MLX Swift app (planned)
```

Each app is its own Xcode project you can open and read on its own. Only the small `LLMEngineKit` package is shared, so studying the llama.cpp app never drags in MLX's dependencies, and all three still implement the same contract.

## The shared abstraction

Every engine sits behind one protocol, `LLMEngine` (in [Packages/LLMEngineKit](Packages/LLMEngineKit/Sources/LLMEngineKit/LLMEngine.swift)):

```swift
public protocol LLMEngine: Sendable {
    static var engineName: String { get }
    static func availability() -> EngineAvailability   // cheap device/OS check
    func load() async throws                           // config is passed at init, not here
    func unload() async
    func generate(_ userMessage: String) async -> AsyncThrowingStream<String, Error>
    func stopGenerating() async
    func resetConversation() async
    var lastMetrics: GenerationMetrics? { get async }  // for the benchmarks
}
```

The engine-specific work stays hidden. llama.cpp's KV-cache handling, MLX's model downloads, and Foundation Models' snapshot diffing all come out as the same stream of text deltas.

### Falling back between engines

Availability is a plain function you can call before loading anything, so a production app can list its engines in order of preference and take the first one that runs:

```swift
let engine = EngineSelector.firstAvailable(from: [
    EngineCandidate(name: "Foundation Models",        // free, nothing to download,
                    availability: FoundationModelsEngine.availability,
                    make: { FoundationModelsEngine() }),  // but needs iOS 26 and an eligible device
    EngineCandidate(name: "MLX",                      // Metal-optimized, device only
                    availability: MLXChatEngine.availability,
                    make: { MLXChatEngine(modelID: "mlx-community/Llama-3.2-1B-Instruct-4bit") }),
    EngineCandidate(name: "llama.cpp",                // runs just about anywhere
                    availability: LlamaEngine.availability,
                    make: { LlamaEngine(modelURL: url, family: .llama3) }),
])   // nil means nothing local can run it, so fall back to cloud or show an error
```

When an engine is not available it says why. Foundation Models, for example, reports whether the device is ineligible, Apple Intelligence is switched off, or the model is still downloading, so the UI can tell the user what to fix.

## Benchmarks

Coming in Phase 4: the same prompts on the same phone (an iPhone 12 with 4 GB, the low end we design for), cold and warm, three runs each, measured through `GenerationMetrics`.

| Engine | Model | Disk | Cold load | TTFT | tok/s | Peak memory | Min OS | Setup |
|---|---|---|---|---|---|---|---|---|
| llama.cpp | Llama 3.2 1B Q4_K_M | 0.8 GB | TBD | TBD | TBD | TBD | app target | 1 SPM dep, 1-file download |
| MLX | Llama 3.2 1B 4-bit | ~0.7 GB | TBD | TBD | TBD | TBD | device with Metal | 1 SPM dep, Hub snapshot |
| Foundation Models | ~3B system model | 0 | TBD | TBD | TBD | TBD | iOS 26 with AI | none |

## Roadmap

- [x] Phase 1: llama.cpp chat app, repo structure, and the `LLMEngineKit` protocol
- [ ] Phase 2: Apple Foundation Models smart-notes app — iOS 26 surface built (streaming chat, guided generation, tools, dynamic schemas, content tagging, transcript persistence); iOS 27 beta features (skills, Private Cloud Compute, phone-a-friend, baton-pass, Spotlight RAG) planned in [PHASE-B-PLAN.md](FoundationModelsChat/PHASE-B-PLAN.md)
- [ ] Phase 3: MLX Swift app (`MLXChatEngine`, Hub snapshot download, Metal cache limits)
- [ ] Phase 4: benchmark suite and the numbers above

## Requirements

- Xcode 26 or newer. The llama.cpp app targets iOS 26.5.
- Use a real device for meaningful speed numbers. The simulator has no Metal backend for ggml or MLX, so llama.cpp falls back to CPU and MLX will not run at all.
- For device builds, set your Development Team and turn on the Increased Memory Limit capability for the App ID.

## License

MIT. See [LICENSE](LICENSE).
