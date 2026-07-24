//
//  SettingsView.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  GenerationOptions controls (applied to every assistant request), the
//  LLMEngineKit availability probe, and the developer debug HUD.
//

import FoundationModels
import LLMEngineKit
import SwiftUI

struct SettingsView: View {
    @Environment(NotesAssistant.self) private var assistant

    private enum Sampling: String, CaseIterable {
        case modelDefault = "Default"
        case greedy = "Greedy"
    }

    @State private var sampling: Sampling = .modelDefault
    @State private var useCustomTemperature = false
    @State private var temperature = 0.7
    @State private var limitTokens = false
    @State private var maxTokens = 500
    @State private var showDebugHUD = false

    var body: some View {
        Form {
            Section {
                Picker("Sampling", selection: $sampling) {
                    ForEach(Sampling.allCases, id: \.self) { mode in
                        Text(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Custom temperature", isOn: $useCustomTemperature)
                if useCustomTemperature {
                    VStack(alignment: .leading) {
                        Slider(value: $temperature, in: 0...2, step: 0.1)
                        Text("Temperature: \(temperature, specifier: "%.1f") — lower is focused, higher is creative")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Limit response length", isOn: $limitTokens)
                if limitTokens {
                    Stepper("Max tokens: \(maxTokens)", value: $maxTokens, in: 100...2000, step: 100)
                }
            } header: {
                Text("Generation Options")
            } footer: {
                Text("Greedy sampling is deterministic for a given model version. These apply to the assistant chat.")
            }

            Section("Engine (LLMEngineKit)") {
                EngineProbeView()
            }

            Section {
                Toggle("Show Debug HUD", isOn: $showDebugHUD)
                if showDebugHUD {
                    DebugHUDView()
                }
            } footer: {
                Text("Token accounting and the KV cache rules for the on-device model.")
            }
        }
        .navigationTitle("Settings")
        .onChange(of: sampling) { _, _ in apply() }
        .onChange(of: useCustomTemperature) { _, _ in apply() }
        .onChange(of: temperature) { _, _ in apply() }
        .onChange(of: limitTokens) { _, _ in apply() }
        .onChange(of: maxTokens) { _, _ in apply() }
    }

    private func apply() {
        assistant.options = GenerationOptions(
            sampling: sampling == .greedy ? .greedy : nil,
            temperature: useCustomTemperature ? temperature : nil,
            maximumResponseTokens: limitTokens ? maxTokens : nil
        )
    }
}

/// Shows the LLMEngineKit availability probe — the same fallback-chain
/// machinery the showcase's other engines plug into.
private struct EngineProbeView: View {
    private let probes = EngineSelector.probeAll([
        EngineCandidate(
            name: FoundationModelsEngine.engineName,
            availability: { FoundationModelsEngine.availability() },
            make: { FoundationModelsEngine() }
        )
    ])

    var body: some View {
        ForEach(probes, id: \.name) { probe in
            HStack {
                Text(probe.name)
                Spacer()
                switch probe.availability {
                case .available:
                    Label("Available", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                case .unavailable(let reason):
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}
