//
//  RootTabView.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Notes / Assistant / Settings. The Notes tab always works (plain SwiftData
//  app); only the AI surfaces are gated on model availability, so the app
//  stays useful on ineligible devices.
//

import SwiftUI

struct RootTabView: View {
    @Environment(AvailabilityGate.self) private var gate
    @Environment(NotesAssistant.self) private var assistant
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            Tab("Notes", systemImage: "note.text") {
                NavigationStack {
                    NotesListView()
                }
            }
            Tab("Assistant", systemImage: "sparkles") {
                NavigationStack {
                    if case .available = gate.state {
                        AssistantChatView(assistant: assistant)
                    } else {
                        AvailabilityGateView()
                    }
                }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    PlaceholderView(title: "Settings", note: "Milestone 6 adds options here.")
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The user may enable Apple Intelligence in Settings and come
            // back, or the model may finish downloading — re-probe.
            if phase == .active { gate.refresh() }
        }
    }
}

/// Temporary milestone placeholder, replaced as features land.
struct PlaceholderView: View {
    let title: String
    let note: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "hammer", description: Text(note))
            .navigationTitle(title)
    }
}

#Preview {
    RootTabView()
        .environment(AvailabilityGate())
}
