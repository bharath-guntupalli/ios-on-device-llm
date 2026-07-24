//
//  BaseRuntime.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  iOS 26 GA runtime: plain LanguageModelSession construction.
//

import Foundation
import FoundationModels

struct BaseRuntime: AssistantRuntime {

    func makeSession(tools: [any Tool],
                     instructions: String?,
                     transcript: Transcript?) -> LanguageModelSession {
        if let transcript {
            return LanguageModelSession(transcript: transcript)
        }
        if let instructions {
            return LanguageModelSession(tools: tools, instructions: instructions)
        }
        return LanguageModelSession(tools: tools)
    }
}
