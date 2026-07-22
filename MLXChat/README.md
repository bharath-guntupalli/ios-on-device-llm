# MLXChat

> Part of the [iOS On-Device LLM Showcase](../README.md). This is the MLX Swift approach.

Status: planned (Phase 2).

The plan:

- Dependencies: [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) for the `MLXLLM` and `MLXLMCommon` products, plus `MLX` itself for `GPU.set(cacheLimit:)` to keep the Metal buffer cache in check on 4 to 6 GB devices.
- Model and weights: `mlx-community/Llama-3.2-1B-Instruct-4bit` (~0.7 GB), the same base model as the llama.cpp app so the benchmarks compare like for like. Weights arrive as a multi-file Hugging Face snapshot through `LLMModelFactory.shared.loadContainer(configuration:progress:)`, not a single file.
- Constraints: Metal only, so it runs on a device and not the simulator. `MLXChatEngine.availability()` returns unavailable on the simulator and checks free memory on a device.
- Engine: a thin `MLXChatEngine` actor conforming to [`LLMEngine`](../Packages/LLMEngineKit/Sources/LLMEngineKit/LLMEngine.swift). MLX already streams deltas, so the adapter stays small.
