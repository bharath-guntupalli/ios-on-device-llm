//
//  FoundationModelsChatApp.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Entry point. The whole app sits behind an availability gate because the
//  on-device foundation model only exists on Apple Intelligence hardware
//  with the feature switched on; every unavailable reason gets its own
//  user-actionable screen instead of a dead assistant tab.
//

import SwiftData
import SwiftUI

@main
struct FoundationModelsChatApp: App {
    @State private var gate = AvailabilityGate()

    private let container: ModelContainer
    private let notesStore: NotesStore

    init() {
        do {
            container = try ModelContainer(for: Note.self)
        } catch {
            fatalError("Could not create SwiftData container: \(error)")
        }
        notesStore = NotesStore(context: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(gate)
                .environment(notesStore)
                .modelContainer(container)
        }
    }
}
