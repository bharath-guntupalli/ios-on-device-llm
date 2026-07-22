# FoundationModelsChat

> Part of the [iOS On-Device LLM Showcase](../README.md). This is the Apple Foundation Models approach.

Status: planned (Phase 3).

The plan:

- Dependencies and weights: none. The roughly 3B system model ships with iOS 26 on Apple Intelligence devices, so there is nothing to download. That is the main reason to reach for it.
- Availability: `SystemLanguageModel.default.availability` maps straight onto `EngineAvailability`. Its `.deviceNotEligible`, `.appleIntelligenceNotEnabled`, and `.modelNotReady` cases each become an `.unavailable(reason:)` the UI can act on. This is the engine that makes the fallback chain worth having.
- The tricky part: `LanguageModelSession.streamResponse(to:)` returns the full text so far on every step, but `LLMEngine` streams deltas, so the adapter subtracts the part it has already emitted.
- Lifecycle: `load()` creates a `LanguageModelSession(instructions:)` and optionally prewarms it, `resetConversation()` starts a fresh session, `stopGenerating()` cancels the task reading the stream, and `unload()` drops the session.
