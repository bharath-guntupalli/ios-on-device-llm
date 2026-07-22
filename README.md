# OnDeviceLLM

A native iOS app that runs large language models **fully on-device** using [llama.cpp](https://github.com/ggml-org/llama.cpp) with Metal GPU acceleration. No server, no API key — download a GGUF model once and chat offline.

Built with SwiftUI, Swift concurrency (`actor` + `AsyncThrowingStream`), and the `@Observable` state pattern. Targets iPhone 12 (4 GB RAM) and newer.

## Features

- **Model catalog** — pick between bundled model definitions (Llama 3.2 1B Instruct, Qwen 2.5 1.5B Instruct, both Q4_K_M). Adding a model is one entry in `ModelCatalog.all`.
- **Resilient downloads** — background `URLSession` keeps transferring while the app is suspended or terminated; pause/resume supported (HTTP Range); files are validated (GGUF magic bytes) and **excluded from iCloud backup**.
- **Streaming inference** — tokens stream into the UI as they decode, with a stop button and multi-turn conversations.
- **KV-cache reuse** — follow-up turns only prefill the new suffix, so second-turn latency is near-instant. When the context budget would overflow, the oldest exchange is trimmed and the cache rebuilt.
- **Memory safety on 4 GB devices** — conservative `n_ctx` (2048), reserved generation budget, `os_proc_available_memory()` checks before load and during generation, and the `com.apple.developer.kernel.increased-memory-limit` entitlement.

## Architecture

```
OnDeviceLLMApp (router) ── AppDelegate (background URLSession event replay)
 ├─ ModelSetupView ── ModelDownloader (@Observable) ── DownloadCoordinator (URLSessionDownloadDelegate)
 └─ ChatView ── ChatViewModel (@Observable) ── LlamaEngine (actor over the llama.cpp C API)
                                                  └─ ChatTemplate (Llama 3 markup / ChatML)
```

| File | Responsibility |
|---|---|
| `Models/ModelCatalog.swift` | Model definitions, local paths, GGUF validation |
| `Download/ModelDownloader.swift` | Background download session + observable UI state |
| `Engine/ChatTemplate.swift` | Exact per-family prompt rendering (full & incremental) |
| `Engine/LlamaEngine.swift` | Model lifecycle, tokenization, KV cache, sampling, streaming |
| `Chat/ChatViewModel.swift` | MainActor bridge between UI and engine |
| `Views/` | Model setup + streaming chat screens |

The `llama.swift` SPM package is a thin re-export of the llama.cpp C API as a prebuilt XCFramework (Metal enabled); all Swift abstractions live in this repo.

## Requirements

- Xcode 26+, iOS 26.5 deployment target
- A physical device for real performance — **the iOS simulator has no Metal backend for ggml**, so the app falls back to CPU there (slow, but functional for UI testing)

## Setup

1. Clone and open `OnDeviceLLM.xcodeproj`. SPM resolves `llama.swift` automatically.
2. Select your **Development Team** under Signing & Capabilities.
3. Make sure the **Increased Memory Limit** capability is enabled for your App ID (the entitlement is already in `OnDeviceLLM.entitlements`; the capability must also exist on the provisioning profile or codesigning fails).
4. Build & run. Download a model from the setup screen, then chat.

Model weights (~0.8–1 GB) download from [Hugging Face (bartowski's GGUF quants)](https://huggingface.co/bartowski) into the app's Documents/Models directory.

## Device test checklist

- Console shows llama.cpp offloading all layers to GPU (`offloaded N/N layers`) on device.
- Second message in a conversation starts streaming almost immediately (KV-cache reuse).
- Start a download, background the app — progress continues; force-quit and relaunch — the download resumes.
- Emoji/CJK output renders correctly (UTF-8 byte buffering across token boundaries).

## Adding a model

Append a `ModelSpec` to `ModelCatalog.all` with the GGUF download URL and the correct `ChatTemplateFamily` (`.llama3` or `.chatML`). For a new prompt format, extend `ChatTemplate`. Keep 1–2 B parameter Q4 quants for 4 GB devices; 3 B+ models need 6 GB+ of RAM.

## Comparison
| Approach | Engine Used | Model Location | Storage Needed | Device Support |
| :--- | :--- | :--- | :--- | :--- |
| **1. Apple Foundation Models Framework** | iOS Native System Service | OS System Partition | 0 MB | Apple Intelligence devices only |
| **2. mlx-swift-examples (LLMEval)** | Apple's MLX Framework | App Documents (`.safetensors`) | ~1GB – 2GB per app | All Apple Silicon (iOS 17+) |
| **3. llama.cpp (llama.swift)** | ggml C-Bindings | App Documents (`.gguf`) | ~800MB – 2GB per app | All Apple Silicon (iOS 16+) |

## License

MIT — see [LICENSE](LICENSE).
