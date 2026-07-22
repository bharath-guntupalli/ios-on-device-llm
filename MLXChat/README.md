# MLXChat

> Part of the [iOS On-Device LLM Showcase](../README.md) — the **MLX Swift** approach.

**Status: 🔜 planned (Phase 2)**

Planned approach:

- **Dependencies:** [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) → `MLXLLM` + `MLXLMCommon` products (plus `MLX` for `GPU.set(cacheLimit:)` to tame the Metal buffer cache on 4–6 GB devices).
- **Model & weights:** `mlx-community/Llama-3.2-1B-Instruct-4bit` (~0.7 GB) — same base model as the llama.cpp app for apples-to-apples benchmarks. Weights arrive as a multi-file Hugging Face repo snapshot via `LLMModelFactory.shared.loadContainer(configuration:progress:)`, not a single-file download.
- **Constraints:** Metal-only — no simulator support, physical device required. `MLXChatEngine.availability()` returns `.unavailable` on the simulator and probes free memory on device.
- **Engine:** a thin `MLXChatEngine` actor conforming to [`LLMEngine`](../Packages/LLMEngineKit/Sources/LLMEngineKit/LLMEngine.swift) (MLX streams deltas natively, so the adapter is small).
