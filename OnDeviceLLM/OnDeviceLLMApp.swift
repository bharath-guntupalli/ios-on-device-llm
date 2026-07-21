//
//  OnDeviceLLMApp.swift
//  OnDeviceLLM
//
//  Created by Guntupalli, Bharath on 21/07/26.
//

import SwiftUI

@main
struct OnDeviceLLMApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Routes between model setup (nothing usable on disk / user picking a model)
/// and the chat screen for the chosen model.
struct RootView: View {
    @State private var activeModel: ModelSpec?

    var body: some View {
        NavigationStack {
            if let model = activeModel {
                ChatView(spec: model) {
                    // "Switch model" — ChatView unloads the engine before
                    // calling back, so we never hold two models in RAM.
                    activeModel = nil
                }
            } else {
                ModelSetupView { spec in
                    activeModel = spec
                }
            }
        }
    }
}

#Preview {
    RootView()
}
