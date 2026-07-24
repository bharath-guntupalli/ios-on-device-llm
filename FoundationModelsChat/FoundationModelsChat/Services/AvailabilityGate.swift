//
//  AvailabilityGate.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Probes SystemLanguageModel availability and turns each unavailable
//  reason into copy the user can act on. This is the framework's designed
//  entry point: check availability cheaply, never assume the model exists.
//

import Foundation
import FoundationModels
import Observation

@Observable
final class AvailabilityGate {

    enum GateAction: Equatable {
        /// Deep-link the user to the Settings app (enable Apple Intelligence).
        case openSettings
        /// The model is still downloading; offer a manual re-check.
        case retry
    }

    enum State: Equatable {
        case available
        case unavailable(title: String, message: String, action: GateAction?)
    }

    private(set) var state: State = .available
    /// Whether the model supports the user's current locale language.
    private(set) var languageSupported = true

    init() {
        refresh()
    }

    func refresh() {
        let model = SystemLanguageModel.default

        switch model.availability {
        case .available:
            state = .available

        case .unavailable(.deviceNotEligible):
            state = .unavailable(
                title: "Device Not Supported",
                message: "Apple Intelligence needs an iPhone 15 Pro or newer (or an Apple silicon iPad or Mac). The Notes tab still works without it.",
                action: nil
            )

        case .unavailable(.appleIntelligenceNotEnabled):
            state = .unavailable(
                title: "Apple Intelligence Is Off",
                message: "Turn on Apple Intelligence in Settings, then come back. The model runs entirely on this device.",
                action: .openSettings
            )

        case .unavailable(.modelNotReady):
            state = .unavailable(
                title: "Model Still Downloading",
                message: "iOS is fetching the on-device model in the background. This usually finishes within a few minutes on Wi-Fi.",
                action: .retry
            )

        case .unavailable(let other):
            // Future reasons the SDK may add — never crash the gate.
            state = .unavailable(
                title: "Model Unavailable",
                message: "The on-device model can't run right now (\(String(describing: other))).",
                action: .retry
            )
        }

        languageSupported = model.supportedLanguages.contains(Locale.current.language)
    }
}
