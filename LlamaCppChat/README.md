# LlamaCppChat (OnDeviceLLM)

> Part of the [iOS On-Device LLM Showcase](../README.md). This is the llama.cpp approach; the engine conforms to the shared [`LLMEngine`](../Packages/LLMEngineKit/Sources/LLMEngineKit/LLMEngine.swift) protocol.

A native iOS app that runs language models on-device with [llama.cpp](https://github.com/ggml-org/llama.cpp) and Metal. No server and no API key: download a GGUF model once, then chat offline.

Built with SwiftUI, an `actor` plus `AsyncThrowingStream` for streaming, and the `@Observable` state pattern. It targets iPhone 12 (4 GB RAM) and up.

## What it does

- A small model catalog (Llama 3.2 1B and Qwen 2.5 1.5B, both Q4_K_M). Adding another model is one entry in `ModelCatalog.all`.
- Downloads that survive backgrounding. A background `URLSession` keeps going while the app is suspended or killed, supports pause and resume over HTTP Range, checks the GGUF magic bytes, and marks the file so iCloud does not back it up.
- Token streaming into the UI as the model decodes, with a stop button and multi-turn chat.
- KV-cache reuse, so a follow-up turn only prefills the new text and the second reply starts almost immediately. If the conversation outgrows the context window, the oldest turn is dropped and the cache is rebuilt.
- Guards for 4 GB devices: a conservative 2048-token context, a reserved generation budget, `os_proc_available_memory()` checks before loading and while generating, and the increased-memory-limit entitlement.

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
| `Download/ModelDownloader.swift` | Background download session and observable UI state |
| `Engine/ChatTemplate.swift` | Per-family prompt rendering, full and incremental |
| `Engine/LlamaEngine.swift` | Model lifecycle, tokenization, KV cache, sampling, streaming |
| `Chat/ChatViewModel.swift` | MainActor bridge between the UI and the engine |
| `Views/` | Model setup and streaming chat screens |

The `llama.swift` package is a thin re-export of the llama.cpp C API as a prebuilt XCFramework with Metal enabled. All the Swift abstractions live in this repo.

## Requirements

- Xcode 26 or newer, iOS 26.5 deployment target.
- A real device for real performance. The iOS simulator has no Metal backend for ggml, so the app falls back to CPU there. It still runs, just slowly, which is fine for UI testing.

## Setup

1. Open `OnDeviceLLM.xcodeproj`. SPM resolves `llama.swift` on its own.
2. Pick your Development Team under Signing & Capabilities.
3. Turn on the Increased Memory Limit capability for your App ID. The entitlement is already in `OnDeviceLLM.entitlements`, but the capability also has to be on the provisioning profile or codesigning fails.
4. Build, run, download a model from the setup screen, then chat.

Model weights (~0.8 to 1 GB) download from [bartowski's GGUF quants on Hugging Face](https://huggingface.co/bartowski) into the app's Documents/Models folder.

## Testing on a device

- The console should show llama.cpp offloading every layer to the GPU (`offloaded N/N layers`).
- The second message in a conversation should start streaming almost immediately, which means the KV cache is being reused.
- Start a download and background the app; it should keep going. Force-quit and relaunch; it should resume.
- Emoji and CJK output should render correctly, since token pieces are buffered until they form valid UTF-8.

## Adding a model

Append a `ModelSpec` to `ModelCatalog.all` with the GGUF download URL and the right `ChatTemplateFamily` (`.llama3` or `.chatML`). For a new prompt format, extend `ChatTemplate`. Stick to 1 to 2 B Q4 quants on 4 GB devices; 3 B and larger models need 6 GB or more of RAM.

## License

MIT. See [LICENSE](../LICENSE).
