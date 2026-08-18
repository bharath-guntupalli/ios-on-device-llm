# FoundationModelsChat

> Part of the [iOS On-Device LLM Showcase](../README.md). This is the **Apple Foundation Models** approach.

A Smart Notes app with an AI assistant, built to exercise as much of Apple's FoundationModels framework as possible. Notes live in SwiftData and get donated to Spotlight; the assistant chats, streams, tags, summarizes, extracts, and calls tools, all with the system model that ships inside iOS. No downloads, no API keys, nothing leaves the device.

The work is split in two phases. **Phase A is built and is what you get when you open this project.** It covers the full iOS 26 surface and runs on the current Xcode.

**Phase B is on hold: it needs Xcode 27 and an iOS 27 device.** That is where skills, Private Cloud Compute, phone-a-friend, baton-pass, and Spotlight RAG live. It is fully researched and written up in [PHASE-B-PLAN.md](PHASE-B-PLAN.md), ready to execute once that toolchain is available, but nothing in this project depends on it today. Phase A stands on its own.

## What Phase A demonstrates

| Feature in the app | Framework API it exercises |
|---|---|
| Assistant tab gates on model state with actionable copy | `SystemLanguageModel.default.availability`, all three `UnavailableReason` cases, `supportedLanguages` |
| Streaming chat with stop and new-conversation | `LanguageModelSession`, `streamResponse` (cumulative snapshots diffed to deltas), `prewarm()`, `isResponding` |
| Auto-tagging when you finish editing a note | `SystemLanguageModel(useCase: .contentTagging)` with a `@Generable` tag shape |
| AI Summary card that fills in field by field | `@Generable` + `@Guide` constraints, `PartiallyGenerated` streaming snapshots |
| Fill Template: you name the fields at runtime, the model extracts them | `DynamicGenerationSchema`, `GenerationSchema(root:dependencies:)`, `GeneratedContent.value(_:forProperty:)` |
| The model searches, creates notes, and sets reminders on its own | Three `Tool` conformances: read-only, stateful, and EventKit-backed with `.anyOf`-constrained arguments |
| Conversation survives relaunch | `Transcript` is Codable; restored via `LanguageModelSession(transcript:)` |
| Long chats condense instead of dying | Catch `exceededContextWindowSize`, rebuild the session from instructions + recent turns, retry once |
| Settings sliders change the output | `GenerationOptions` (greedy vs default sampling, temperature, max tokens) |
| Debug HUD with real token numbers | `contextSize` and `tokenCount(for:)` (iOS 26.4) plus the KV cache append-vs-rewrite rules |
| Friendly failure states | `LanguageModelSession.GenerationError` mapping: guardrail, refusal, rate limit, assets unavailable |
| Showcase engine adapter | `FoundationModelsEngine` conforms to the shared [`LLMEngine`](../Packages/LLMEngineKit/Sources/LLMEngineKit/LLMEngine.swift) protocol |

## Requirements

- Xcode 26 or newer. Deployment target is iOS 26.0.
- **A physical Apple Intelligence device** (iPhone 15 Pro or newer) with Apple Intelligence enabled. The framework does not run in the iOS Simulator; the simulator compiles the app and shows the availability-gate screen, which is itself one of the features.
- A Development Team set under Signing & Capabilities for device builds.

That is everything Phase A needs. Phase B is a different story: it is **on hold until Xcode 27 and an iOS 27 device are available**, and no part of it can be built or even compiled before then. See [PHASE-B-PLAN.md](PHASE-B-PLAN.md).

## Architecture

```
FoundationModelsChatApp ── ModelContainer (Note, ChatSessionRecord)
 ├─ Notes tab ── NotesListView / NoteEditorView ── NotesStore ── SpotlightIndexer
 │                ├─ NoteAIActionsView (streamed NoteSummary card)
 │                └─ TemplateFillView (DynamicGenerationSchema)
 ├─ Assistant tab ── AssistantChatView ── AssistantViewModel ── NotesAssistant
 │                     └─ AvailabilityGateView (when the model can't run)
 └─ Settings tab ── GenerationOptions controls, engine probe, DebugHUD

NotesAssistant ── AssistantRuntime (seam) ── Runtime26/BaseRuntime   [Phase A, built]
                                          └─ Runtime27/…            [Phase B, on hold]
Engine/FoundationModelsEngine ── LLMEngineKit conformance (snapshot→delta)
Tools/ ── SearchNotesTool · CreateNoteTool · CalendarTool
```

Where the shared protocol ends: `LLMEngine` is a string-in, string-out contract, which is exactly what the three-engine comparison needs. Tools, structured output, and transcript surgery don't fit that shape, so they live in `NotesAssistant`. The engine adapter is honest about this split, and the Settings tab shows the `EngineSelector` probe working against it.

Every note save donates a `CSSearchableItem` (title, body, tags) under a stable UUID. That makes notes searchable from system Spotlight today, and it quietly builds the retrieval corpus that the on-hold `SpotlightSearchTool` RAG mode will search whenever Phase B becomes possible.

## Prompt safety posture

Instructions are trusted and composed only from developer constants; user chat text and note bodies travel exclusively as prompt content. The model is trained to prioritize instructions over prompts, which is the first line of defense against prompt injection. Guardrail hits and refusals are treated as normal outcomes with friendly copy, not crashes.

## Documented but not implemented

- **LoRA adapters**: `SystemLanguageModel(adapter:)` can load a custom-trained adapter (~160 MB, rank 32, trained with Apple's Python toolkit). Each adapter is pinned to a base model version and must be retrained when Apple updates it. Try instructions and guided generation first; adapters are a last resort.
- **#Playground macro**: in Xcode 26 you can put `#Playground { }` next to your code and iterate on prompts with live results in the canvas. Works best with "My Mac" as the destination on an Apple Intelligence Mac.
- **Foundation Models Instrument**: an Instruments template for profiling request latency and seeing when the KV cache gets invalidated.

## Phase B, on hold: needs Xcode 27 and an iOS 27 device

Skills (including user-authored ones), Private Cloud Compute with reasoning levels and token usage, phone-a-friend and baton-pass multi-model orchestration, "ask my notes" RAG via SpotlightSearchTool, and vision attachments. All of it is researched, designed, and written down in [PHASE-B-PLAN.md](PHASE-B-PLAN.md).

None of it can start until Xcode 27 and an iOS 27 device exist on the machine, so it is parked. Phase A is complete and useful without it, and the `AssistantRuntime` protocol in the code is the seam Phase B will plug into, so picking this back up should not require reworking anything that is already built.

## Future RAG roadmap

Two ways to give the assistant real retrieval over the notes corpus. The easier one is currently blocked, which makes the harder one the only path open today.

**Option 1: SpotlightSearchTool. On hold: needs Xcode 27 and an iOS 27 device.** iOS 27 ships a system tool in the CoreSpotlight framework that plugs straight into a `LanguageModelSession`. The OS builds on-device semantic matching over the `CSSearchableItem`s this app already donates; the model writes its own queries and grounds its answers in the results. No embeddings pipeline, no vector store. Real usage shape:

```swift
let tool = SpotlightSearchTool(configuration: .init(
    sources: [CoreSpotlightSource(fetchAttributes: [...])]
))
let session = LanguageModelSession(tools: [tool])
```

**Option 2: Custom embeddings. Available today, and the only RAG path not blocked.** Needs nothing beyond iOS 26, so this is where to start if retrieval matters sooner than Xcode 27 does. FoundationModels has no embedding API and Apple's internal embedding model is not exposed, so you build retrieval yourself: `NLContextualEmbedding` from the NaturalLanguage framework (512-dim on iOS, mean-pool the per-token vectors), brute-force cosine similarity via Accelerate (fine up to roughly 10k chunks), then a real vector store (VecturaKit, SVDB, sqlite-vec, ObjectBox, or USearch) when scale demands. Chunk at 200 to 400 tokens with top-k of 3 to 5, and budget the assembled prompt with `tokenCount(for:)` against the ~4k context window.

Core Spotlight's programmatic search (`CSUserQuery`) is a complement, not a retriever: it hides raw vectors and gives you almost no ranking control.

## References

Apple documentation
- [Foundation Models framework](https://developer.apple.com/documentation/foundationmodels)
- [Human Interface Guidelines: Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai)
- [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [Core Spotlight](https://developer.apple.com/documentation/corespotlight)
- [Adapter training toolkit](https://developer.apple.com/apple-intelligence/foundation-models-adapter/)

WWDC sessions
- [WWDC25 286: Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
- [WWDC25 301: Deep dive into the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/301/)
- [WWDC25 248: Explore prompt design and safety](https://developer.apple.com/videos/play/wwdc2025/248/)
- [WWDC25 259: Code-along: on-device AI with Foundation Models](https://developer.apple.com/videos/play/wwdc2025/259/)
- [WWDC26 241: What's new in the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2026/241/)
- [WWDC26 242: Build agentic app experiences](https://developer.apple.com/videos/play/wwdc2026/242/)
- [WWDC26 246: LLM search using Core Spotlight](https://developer.apple.com/videos/play/wwdc2026/246/)

GitHub
- [apple/foundation-models-utilities](https://github.com/apple/foundation-models-utilities) (Skills API, history modifiers, ChatCompletions model; iOS 27+)

## License

MIT. See [LICENSE](../LICENSE).
