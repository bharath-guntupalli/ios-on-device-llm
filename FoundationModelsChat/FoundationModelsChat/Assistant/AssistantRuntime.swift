//
//  AssistantRuntime.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  The Phase A / Phase B seam. Phase A ships BaseRuntime (plain sessions,
//  iOS 26 GA APIs).
//
//  Phase B is ON HOLD: it needs Xcode 27 and an iOS 27 device. When that
//  toolchain exists, it adds a ProfileRuntime in Assistant/Runtime27/ built
//  on Dynamic Profiles, PCC model selection, skills, and history modifiers,
//  without touching any call site that consumes this protocol. That folder
//  does not exist yet, so do not go looking for it. See PHASE-B-PLAN.md.
//

import Foundation
import FoundationModels

protocol AssistantRuntime {
    /// Builds a fresh session. `transcript` (when present) restores a prior
    /// conversation and wins over `instructions`.
    func makeSession(tools: [any Tool],
                     instructions: String?,
                     transcript: Transcript?) -> LanguageModelSession
}
