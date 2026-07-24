//
//  FMErrorPresenter.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Maps every Foundation Models failure to copy a user can act on.
//  Guardrail hits and refusals are normal, expected outcomes for an
//  on-device safety-filtered model, so they get friendly explanations
//  rather than raw error dumps.
//

import Foundation
import FoundationModels

enum FMErrorPresenter {

    /// True when the error means "conversation too long" and the caller
    /// should condense the transcript and retry.
    static func isContextOverflow(_ error: Error) -> Bool {
        if let generationError = error as? LanguageModelSession.GenerationError,
           case .exceededContextWindowSize = generationError {
            return true
        }
        return false
    }

    static func message(for error: Error) -> String {
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            if error is CancellationError { return "" }
            return error.localizedDescription
        }

        switch generationError {
        case .exceededContextWindowSize:
            return "The conversation got too long for the on-device model. I condensed it and you can continue."
        case .guardrailViolation:
            return "That request touched the model's safety filter. Try rephrasing it."
        case .unsupportedLanguageOrLocale:
            return "The on-device model doesn't support this language yet."
        case .assetsUnavailable:
            return "The model assets aren't available right now. Check that Apple Intelligence is enabled and try again."
        case .rateLimited:
            return "The system is rate-limiting requests. Keep the app in the foreground and try again shortly."
        case .refusal:
            return "The model declined to answer that request."
        default:
            return generationError.localizedDescription
        }
    }
}
