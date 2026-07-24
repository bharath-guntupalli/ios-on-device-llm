//
//  AvailabilityGateView.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Full-screen state for every SystemLanguageModel unavailable reason.
//  Bonus: this screen is the one AI surface you can verify in the
//  simulator, which always reports the model as unavailable.
//

import SwiftUI

struct AvailabilityGateView: View {
    @Environment(AvailabilityGate.self) private var gate

    var body: some View {
        Group {
            if case .unavailable(let title, let message, let action) = gate.state {
                ContentUnavailableView {
                    Label(title, systemImage: "sparkles.slash")
                } description: {
                    VStack(spacing: 8) {
                        Text(message)
                        if !gate.languageSupported {
                            Text("Note: the model may not support your current language yet.")
                                .font(.caption)
                        }
                    }
                } actions: {
                    switch action {
                    case .openSettings:
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)

                    case .retry:
                        Button("Check Again") {
                            gate.refresh()
                        }
                        .buttonStyle(.borderedProminent)

                    case nil:
                        EmptyView()
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Assistant")
    }
}

#Preview {
    NavigationStack {
        AvailabilityGateView()
            .environment(AvailabilityGate())
    }
}
