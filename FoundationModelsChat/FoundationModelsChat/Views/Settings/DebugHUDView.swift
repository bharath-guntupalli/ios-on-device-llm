//
//  DebugHUDView.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Developer-facing token accounting. contextSize and tokenCount(for:)
//  arrived in iOS 26.4 — on earlier systems the HUD shows the documented
//  4,096-token constant instead.
//

import FoundationModels
import SwiftUI

struct DebugHUDView: View {
    @Environment(NotesAssistant.self) private var assistant

    @State private var contextSize: Int?
    @State private var transcriptTokens: Int?
    @State private var sampleText = "How many tokens is this sentence?"
    @State private var sampleTokens: Int?

    var body: some View {
        Group {
            LabeledContent("Context window") {
                Text(contextSize.map { "\($0) tokens" } ?? "4096 tokens (documented, pre-26.4)")
            }
            .font(.caption)

            LabeledContent("Transcript entries") {
                Text("\(assistant.transcript.count)")
            }
            .font(.caption)

            if let transcriptTokens {
                LabeledContent("Transcript tokens") {
                    Text("\(transcriptTokens)")
                }
                .font(.caption)
            }

            VStack(alignment: .leading, spacing: 4) {
                TextField("Sample text to count", text: $sampleText)
                    .font(.caption)
                HStack {
                    Button("Count Tokens") { countTokens() }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    if let sampleTokens {
                        Text("\(sampleTokens) tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            DisclosureGroup {
                Text("""
                Appending turns to a session preserves the KV cache, so \
                follow-up prompts prefill only the new suffix. Rewriting \
                the transcript prefix (condensing history, changing \
                instructions or tools) invalidates the cache and the next \
                turn pays a full prefill. That's why this app condenses \
                only when the window overflows.
                """)
                .font(.caption2)
                .foregroundStyle(.secondary)
            } label: {
                Text("KV cache rules")
                    .font(.caption)
            }
        }
        .task {
            readModelLimits()
        }
    }

    private func readModelLimits() {
        if #available(iOS 26.4, *) {
            contextSize = SystemLanguageModel.default.contextSize
        }
    }

    private func countTokens() {
        Task {
            if #available(iOS 26.4, *) {
                sampleTokens = try? await SystemLanguageModel.default.tokenCount(for: sampleText)
            } else {
                sampleTokens = nil
            }
        }
    }
}
