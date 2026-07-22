# FoundationModelsChat

> Part of the [iOS On-Device LLM Showcase](../README.md) — the **Apple Foundation Models** approach.

**Status: 🔜 planned (Phase 3)**

Planned approach:

- **Dependencies & weights:** none — the ~3B system language model ships with iOS 26+ on Apple Intelligence-eligible devices. Zero download is the headline advantage of this path.
- **Availability:** `SystemLanguageModel.default.availability` maps directly onto the shared `EngineAvailability` type — `.deviceNotEligible`, `.appleIntelligenceNotEnabled`, and `.modelNotReady` each become an `.unavailable(reason:)` the UI can act on. This is the engine that motivates the fallback chain.
- **Key adapter detail:** `LanguageModelSession.streamResponse(to:)` yields **cumulative snapshots**, while the [`LLMEngine`](../Packages/LLMEngineKit/Sources/LLMEngineKit/LLMEngine.swift) contract streams **deltas** — the adapter diffs each snapshot against the previously emitted prefix.
- **Lifecycle mapping:** `load()` = create `LanguageModelSession(instructions:)` (+ optional `prewarm()`); `resetConversation()` = fresh session; `stopGenerating()` = cancel the consuming task; `unload()` = drop the session.
