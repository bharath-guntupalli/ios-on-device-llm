# Phase B Implementation Plan: iOS 27 Features

> **ON HOLD: needs Xcode 27 and an iOS 27 device.**
>
> As of August 2026 the development machine has Xcode 26.6 and no iOS 27 SDK or simulator runtime, so none of the work below can be built, run, or even compiled. Do not start it.
>
> Nothing else in the repo is blocked by this. The Foundation Models app's Phase A is complete and runs on iOS 26, and the MLX app (Phase 3) needs nothing beyond Xcode 26. Pick this file back up when the toolchain arrives; the plan is preserved exactly as researched, and every `[verify against SDK]` flag in it still needs checking against the shipping SDK, since these APIs were documented from beta material.

This document is a self-contained implementation handoff. Give it to an AI coding agent (or follow it yourself) once the prerequisites below are met. It assumes Phase A of FoundationModelsChat is complete and committed (milestones M1 to M6: scaffold, notes + Spotlight donation, streaming chat, tagging + guided generation, tools + dynamic templates, transcript persistence + debug HUD).

Everything here was researched in July 2026 against Apple documentation, WWDC26 sessions 241/242/246, and the apple/foundation-models-utilities source. iOS 27 APIs are BETA: names may shift before GA. Where an exact symbol is uncertain it is marked **[verify against SDK]**. The architecture quarantines all beta symbols in one folder so renames stay cheap.

---

## 0. Prerequisites (blocking)

1. **Xcode 27 beta** installed side by side with Xcode 26.x. Check with `ls /Applications | grep -i xcode`. Use `xcodes` or developer.apple.com/downloads. Select per-invocation with `DEVELOPER_DIR=/Applications/Xcode-27-beta.app xcodebuild ...` or point XcodeBuildMCP at it.
2. **A physical iPhone 15 Pro or newer running iOS 27 beta** with Apple Intelligence enabled. FoundationModels does not run in the iOS Simulator. Note: Xcode 26.x cannot deploy to an iOS 27 device; all device testing goes through Xcode 27 beta.
3. **DEVELOPMENT_TEAM set** in FoundationModelsChat.xcodeproj (Signing & Capabilities in Xcode, or add `DEVELOPMENT_TEAM = <TEAMID>;` to both target build configurations in project.pbxproj).
4. Working tree clean, Phase A pushed.

Build verification throughout: compile against an iOS 27 simulator (`build_sim`) for fast feedback; run features on the device. The simulator's availability gate will report the model unavailable, which is expected.

## Architecture recap (what Phase A left ready)

- `Assistant/AssistantRuntime.swift` defines the seam:
  ```swift
  protocol AssistantRuntime {
      func makeSession(tools: [any Tool], instructions: String?, transcript: Transcript?) -> LanguageModelSession
  }
  ```
  `Runtime26/BaseRuntime` is the Phase A implementation. Phase B adds `Runtime27/` implementations WITHOUT changing any call site of `NotesAssistant`.
- `NotesAssistant` owns the live session, snapshot-to-delta streaming, overflow condensing, and the instructions-trusted / prompt-untrusted split.
- Every note save donates a `CSSearchableItem` (uniqueIdentifier = note UUID string, domainIdentifier `BharathGuntupalli.FoundationModelsChat.notes`, title + textContent + keywords). This is the RAG corpus for M11.
- File header convention: `Created by Guntupalli, Bharath on <DD/MM/YY>.` Conventional commits, no attribution lines.

---

## M7 — `chore(fm): raise deployment target to iOS 27 and add FoundationModelsUtilities`

1. In `FoundationModelsChat.xcodeproj/project.pbxproj`, change both `IPHONEOS_DEPLOYMENT_TARGET = 26.0;` entries to `27.0`.
2. Add the remote package (pbxproj edits, mirroring how LlamaCppChat wires llama.swift):
   - `XCRemoteSwiftPackageReference` with `repositoryURL = "https://github.com/apple/foundation-models-utilities"; requirement = { kind = upToNextMajorVersion; minimumVersion = 1.0.0; }` — pin whatever the latest tag is; the repo is marked experimental, so pin, don't track main.
   - `XCSwiftPackageProductDependency` with `productName = FoundationModelsUtilities` (include the `package =` field pointing at the remote reference; remote refs need it, local ones don't).
   - Entries in `PBXProject.packageReferences`, `PBXNativeTarget.packageProductDependencies`, a `PBXBuildFile`, and the Frameworks build phase.
3. Create the folder `FoundationModelsChat/Assistant/Runtime27/` (all beta symbols live ONLY here plus the thin views that render their state).
4. Facts about FoundationModelsUtilities (verified from source, July 2026): swift-tools 6.2, platforms iOS/macOS/visionOS/watchOS 27.0, single product `FoundationModelsUtilities`, Apache-2.0. Provides `Skill`, `Skills`, `SkillActivations`, `SkillsBuilder`; history modifiers `.summarizeHistory(entryThreshold:model:)`, `.rollingWindow(entries:)` / `.rollingWindow(size:)`, `.droppingCompletedToolCalls()`; and `ChatCompletionsLanguageModel(name:url:supportsGuidedGeneration:additionalHeaders:)`. **No built-in skills ship** — the app authors its own. The repo's `skills/foundation-models-utilities/SKILL.md` is an agent-readable API guide; read it first.
5. Verify: project builds with Xcode 27 beta against an iOS 27 simulator; the Phase A app still runs end to end on the device.

## M8 — `feat(assistant): Private Cloud Compute backend with reasoning and usage`

New file `Runtime27/ModelBackend.swift`:
```swift
enum ModelBackend {
    case onDevice
    case privateCloud(reasoning: ReasoningLevel)   // [verify against SDK] exact ReasoningLevel spelling
}
```
Facts (WWDC26 241): third-party PCC access, 32,000-token context, reasoning levels, no API keys, prompts not stored, free below 2M first-time downloads, daily usage limits (higher with iCloud+). Usage shape from the session recap:
```swift
let session = LanguageModelSession(model: PrivateCloudComputeLanguageModel())   // [verify against SDK]
let response = try await session.respond(to: prompt,
    contextOptions: ContextOptions(reasoningLevel: .light))                      // [verify against SDK]
```
Implementation:
1. Extend `AssistantRuntime` conformers: a `Runtime27/ProfileRuntime.swift` (or extend BaseRuntime) that builds the session with the selected backend's model.
2. `NotesAssistant`: add `var backend: ModelBackend` and rebuild the session when it changes (note: switching models mid-conversation resets the KV cache; carry the transcript over via `makeSession(transcript:)`).
3. UI: a model picker in the chat toolbar (On-Device / Private Cloud Compute), a reasoning-level control shown only for PCC, and a per-message usage footer reading `response.usage.input.totalTokenCount`, `.input.cachedTokenCount`, `.output.totalTokenCount` **[verify against SDK]**. Streaming responses may expose usage on the final snapshot or the response object; check both.
4. Device verification: PCC answers arrive with usage counts; airplane mode makes PCC unavailable while on-device keeps working (surface that state cleanly); reasoning `.deep` visibly increases latency and answer depth.

## M9 — `feat(skills): built-in and user-authored skills with activation chips`

Facts (verified from foundation-models-utilities source):
- Prompt-based skill (KV-cache friendly, one-shot): `Skill(name:description:prompt:)` or trailing `@PromptBuilder` closure. Activation injects the prompt as tool OUTPUT, so the cached prefix survives.
- Instructions-based skill (stateful, cache-invalidating, can bundle tools): `Skill(name:description:instructions:allowsDeactivation:)` or `@DynamicInstructionsBuilder` closure containing `Instructions(...)` plus `Tool` instances that only exist while the skill is active.
- `Skills(activations:) { ... }` conforms to `DynamicInstructions` and synthesizes a tool named `activate_skill` (or `toggle_skill` when any skill allows deactivation). **The model self-activates skills** based on their descriptions; there is no imperative invoke call. `SkillActivations` is `@Observable` (`activate/deactivate/isActive/activeSkillNames`).
- `SkillsBuilder` supports `for`-`in`, which is what makes user-authored skills possible.
- Skills require the Dynamic Profiles session shape (`LanguageModelSession.DynamicProfile` / `Profile { }` builder from WWDC26 242) **[verify against SDK]** — this is where `Runtime27/ProfileRuntime.swift` becomes the real runtime: `Profile { Instructions(...); tools...; Skills(...) }`.

Implementation:
1. New SwiftData model `SkillDefinition` (name, detail, promptText, createdAt) + migrate the ModelContainer schema.
2. `Runtime27/SkillsCatalog.swift`:
   ```swift
   Skills(activations: activations) {
       Skill(name: "grammar-fixer", description: "Rewrites text with correct grammar and spelling",
             prompt: "Rewrite the user's text grammatically...")
       Skill(name: "summarizer", description: "Summarizes long content into bullets",
             instructions: "Summarize long content into tight bullet points.", allowsDeactivation: true)
       Skill(name: "style-guide", description: "Applies the user's writing style guide",
             prompt: userStyleText)                                    // editable in Settings
       for def in userSkills { Skill(name: def.name, description: def.detail, prompt: def.promptText) }
   }
   ```
3. UI: `SkillsManagerView` + `SkillEditorView` (create/edit/delete `SkillDefinition`s — this is the create-your-own-skill flow), and a `SkillChipsRow` above the chat input observing `SkillActivations.activeSkillNames` with manual toggle.
4. Device verification: "fix this sentence: me and him goes yesterday" self-activates grammar-fixer (chip lights up); a user-created skill activates from its description; deactivation works for the summarizer.

## M10 — `feat(profiles): deep-answer phone-a-friend and brainstorm baton-pass`

Definitions (WWDC26 242, verified):
- **Phone-a-friend = consultation.** A tool spawns a short-lived CHILD session with an ISOLATED transcript (often on a bigger model), asks one thing, returns the answer. The parent always writes the final reply.
  ```swift
  struct DeepAnswerTool: Tool {
      let name = "deepAnswer"
      let description = "Consults a more capable model for hard analytical questions."
      @Generable struct Arguments { var question: String }
      func call(arguments: Arguments) async throws -> String {
          let child = LanguageModelSession(model: PrivateCloudComputeLanguageModel())  // isolated
          return try await child.respond(to: arguments.question).content
      }
  }
  ```
  Set an `@Observable` flag when it fires; show a "PCC consulted" badge on the answer bubble.
- **Baton-pass = collaboration.** Two profiles SHARE one continuous transcript; a tool call flips which profile is active. WWDC shape:
  ```swift
  switch mode {
  case .brainstorm:
      Profile { BrainstormInstructions(); SwitchModeTool() }
          .onToolCall { orchestrator.mode = .organize }
          .model(pccModel)
  case .organize:
      Profile { OrganizeInstructions(); SwitchModeTool() }
          .onToolCall { orchestrator.mode = .brainstorm }
          .model(onDeviceModel)
  }
  ```
  **[verify against SDK]**: `Profile`, `.onToolCall`, `.model()`, `toolCallingMode` spellings.
- Also wire the FoundationModelsUtilities history modifiers onto the profile (`.rollingWindow(entries:)`, `.summarizeHistory(entryThreshold:model:)`, `.droppingCompletedToolCalls()`) with Debug HUD toggles so their token effects are observable. Canonical composition order (from the package docs): droppingCompletedToolCalls → rollingWindow → summarizeHistory, outside-in.
- Files: `Runtime27/DeepAnswerTool.swift`, `Runtime27/BrainstormProfiles.swift`, chat UI additions `PCCBadge.swift`, `BrainstormModeIndicator.swift`, a "Brainstorm mode" toggle in the chat toolbar.
- Device verification: badge appears only when the tool actually fired; brainstorm mode visibly flips personas mid-conversation while retaining shared context; iOS 27's settable `session.transcript` (only while `isResponding == false`) can replace the M6 condense-and-rebuild path **[verify against SDK]**.

## M11 — `feat(rag): ask-my-notes mode via SpotlightSearchTool`

Facts (verified against Apple docs July 2026):
- `SpotlightSearchTool` is a struct in the **CoreSpotlight** framework (import CoreSpotlight + FoundationModels), iOS/iPadOS/macOS/Mac Catalyst/visionOS 27.0 beta. It conforms to the FoundationModels `Tool` protocol.
- Real initializer: `SpotlightSearchTool(configuration: SpotlightSearchTool.Configuration)`; also a no-argument `SpotlightSearchTool()`. Configuration takes `sources:` and `customStages:` (ranking/boost stages). `CoreSpotlightSource(fetchAttributes: [SearchableItemAttribute])` selects which donated attributes reach the model (there is NO zero-arg `CoreSpotlightSource()`); an optional `CSSearchableIndexDelegate` variant rehydrates full items. `FileSource` also exists.
- The MODEL writes the search queries; results feed back as grounding context automatically. Observe `tool.searchResults` (an `AsyncSequence` of `SearchReply` — items, scored items, groups, counts; track `queryToken` since the model may search multiple times per turn) to drive UI.
- Implementation: `Runtime27/SpotlightRAG.swift` builds the tool over the notes the app has been donating since Phase A; an "Ask my notes" mode toggle in the chat injects it into the session; `RetrievedNotesStrip.swift` renders the retrieved items above the answer, tappable through to the note (uniqueIdentifier is the note UUID string).
- Device verification: create notes about a distinctive topic, relaunch, ask "what did I write about <topic>?" — the answer cites actual note content and the strip shows the retrieved items; a question about nothing in the notes says so instead of hallucinating.

## M12 — `feat(notes): image attachments with vision description` (stretch, droppable)

iOS 27 vision attachments: `session.respond { "What is in this image?"; Attachment(image) }` accepting UIImage/CGImage/CIImage/pixel buffers/file URLs **[verify against SDK]**. Implementation: PhotosPicker in NoteEditorView storing into the existing `note.imageData`; a "Describe image" action in the AI section appending the description to the body; `Runtime27/VisionActions.swift`. Skip without guilt if the beta API is unstable.

## M13 — `docs: Phase B results and root roadmap update`

Update this app's README: move Phase B rows into the "What it demonstrates" table, record any API-name corrections discovered against the shipping SDK (they are the most valuable notes in the repo), update the root README status column, delete or archive this plan file.

## Risks and notes

- Every `[verify against SDK]` above is a name that came from WWDC26 recaps or beta docs. Budget the first hour of M8/M9/M10 for compile-and-correct against the real SDK; keep corrections in the commit messages.
- FoundationModelsUtilities is self-described as experimental. Pin the version. Its SKILL.md mentions SwiftPM traits that the Package.swift on main does not declare; assume the single product exposes everything.
- PCC has daily usage limits: don't put PCC calls in loops (e.g., don't use it for auto-tagging).
- The Phase A `AssistantRuntime` seam means none of M8 to M11 should require touching `AssistantViewModel`, `AssistantChatView` internals, or any Notes-tab code beyond additive UI.
