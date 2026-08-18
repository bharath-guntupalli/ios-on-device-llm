# MLXChat

> Part of the [iOS On-Device LLM Showcase](../README.md). This is the MLX Swift approach.

Status: not started. This is Phase 3, and it is the next thing that can actually be built, because MLX needs nothing beyond the Xcode 26 that is already installed. The notes below were re-verified in August 2026 and correct several things that had gone stale.

## Dependencies

The libraries moved. `MLXLLM` and `MLXLMCommon` now live in [ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm), not in `mlx-swift-examples`, which has not been tagged since October 2025 and should not be used for new work. Pin `mlx-swift-lm` at 3.31.4 or newer and `mlx-swift` at 0.31.6 or newer, since 0.31.6 specifically fixes an iOS build problem. Tokenizers and the Hugging Face Hub client are now separate packages (`swift-transformers` and `swift-huggingface`).

One thing to watch, and the only place iOS 27 touches this app: `mlx-swift-lm` also vends an `MLXFoundationModels` product that requires the iOS 27 SDK, behind a SwiftPM trait that is on by default. As long as we do not link that product, SwiftPM never compiles it and MLX stays perfectly buildable on Xcode 26. Link `MLXLLM`, `MLXLMCommon`, and `MLXHuggingFace` only.

## Model and weights

`mlx-community/Llama-3.2-1B-Instruct-4bit`, about 695 MB on disk. Same base model as the llama.cpp app so the Phase 4 benchmarks compare like for like, and there is a built-in registry constant for it (`LLMRegistry.llama3_2_1B_4bit`, formerly `ModelRegistry`).

Weights arrive as a multi-file Hugging Face snapshot, not a single file, so the single-file `ModelDownloader` from the llama.cpp app does not transfer. Loading goes through `loadModelContainer`, which in the 3.x API takes a downloader and a tokenizer loader alongside the configuration, and reports a Foundation `Progress` for the UI:

```swift
let container = try await loadModelContainer(
    from: #hubDownloader(HubClient()),
    using: #huggingFaceTokenizerLoader(),
    configuration: LLMRegistry.llama3_2_1B_4bit
) { progress in
    // progress.fractionCompleted drives the download UI
}
```

By default the Hub client puts weights in `Library/Caches`, which iOS is free to purge under disk pressure. For a 695 MB download that is the wrong place, so point `HubCache` at a fixed directory and mark it excluded from backup, the same treatment `ModelDownloader` already gives GGUF files in the llama.cpp app.

## Constraints

MLX is Metal only, and the iOS Simulator does not provide the Metal GPU family it needs. The app compiles for the simulator and then fails at runtime on a Metal assertion about non-uniform threadgroup sizes, so simulator builds are compile checks and UI work only. Apple's documented workaround is to add a "Mac (Designed for iPad)" destination, which runs the same iOS binary against a real GPU on the Mac. Which development path to take is still an open decision; the alternative is device-only, the way the other two apps are set up.

Memory is the other constraint. `GPU.set(cacheLimit:)` is deprecated in favour of `MLX.Memory.cacheLimit`, and Apple's own iOS guidance is a deliberately small buffer cache, on the order of 20 MB for an LLM, tuned upward only if throughput disappoints. Jetsam is the real failure mode on a 4 to 6 GB iPhone, so keep the 4-bit weights, consider the increased-memory-limit entitlement that the llama.cpp app already uses, and call `Memory.clearCache()` on a memory warning.

## Engine

A thin `MLXChatEngine` actor conforming to [`LLMEngine`](../Packages/LLMEngineKit/Sources/LLMEngineKit/LLMEngine.swift). Two things make this adapter smaller than the other two:

- `ChatSession.streamResponse(to:)` yields incremental deltas, which is exactly what `LLMEngine` promises, so there is no diffing to do. Compare `FoundationModelsEngine`, which has to subtract the prefix out of cumulative snapshots.
- Chat templating is automatic. MLXLMCommon applies the model's own chat template through the tokenizer, so there is no equivalent of the hand-rolled `ChatTemplate.swift` that the llama.cpp app needs for Llama 3 and ChatML markup.

`MLXChatEngine.availability()` should report unavailable on the simulator and check free memory on a device. Note that `ChatSession` is not thread safe, so one session per conversation, and it holds its transcript until `clear()`.
