//
//  AssistantRuntime.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  The Phase A / Phase B seam. Phase A ships BaseRuntime (plain sessions,
//  iOS 26 GA APIs). Phase B adds a ProfileRuntime in Assistant/Runtime27/
//  built on Dynamic Profiles, PCC model selection, skills, and history
//  modifiers — without touching any call site that consumes this protocol.
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
