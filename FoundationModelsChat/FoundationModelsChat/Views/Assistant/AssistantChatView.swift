//
//  AssistantChatView.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Streaming chat over the on-device system model. prewarm() fires on
//  appear so the first reply doesn't pay the model-load cost.
//

import SwiftUI

struct AssistantChatView: View {
    @State private var viewModel: AssistantViewModel
    @State private var draft = ""

    init(assistant: NotesAssistant) {
        _viewModel = State(initialValue: AssistantViewModel(assistant: assistant))
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error)
            }
            inputBar
        }
        .navigationTitle("Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.newConversation()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .disabled(viewModel.isGenerating || viewModel.messages.isEmpty)
            }
        }
        .onAppear {
            viewModel.prewarm()
        }
    }

    private var transcript: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if viewModel.messages.isEmpty {
                    ContentUnavailableView(
                        "On-Device Assistant",
                        systemImage: "sparkles",
                        description: Text("Runs entirely on this iPhone with Apple's system model. Nothing leaves the device.")
                    )
                    .padding(.top, 60)
                }
                ForEach(viewModel.messages) { message in
                    MessageBubbleView(
                        message: message,
                        isStreaming: viewModel.isGenerating
                            && message.id == viewModel.messages.last?.id
                    )
                }
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask anything…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(viewModel.isGenerating)
                .onSubmit(send)

            if viewModel.isGenerating {
                Button {
                    viewModel.stop()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.title)
                        .foregroundStyle(.red)
                }
                .accessibilityLabel("Stop generating")
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
        }
        .padding()
        .background(.bar)
    }

    private func send() {
        let text = draft
        draft = ""
        viewModel.send(text)
    }
}
