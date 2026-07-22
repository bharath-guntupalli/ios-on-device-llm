//
//  ChatView.swift
//  OnDeviceLLM
//
//  Created by Guntupalli, Bharath on 21/07/26.
//
//  Live streaming chat. The assistant bubble fills token-by-token as the
//  engine's AsyncThrowingStream yields text fragments.
//

import LLMEngineKit
import SwiftUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var draft = ""
    /// Called after the engine is unloaded, to route back to model selection.
    let onSwitchModel: () -> Void

    init(spec: ModelSpec, onSwitchModel: @escaping () -> Void) {
        _viewModel = State(initialValue: ChatViewModel(spec: spec))
        self.onSwitchModel = onSwitchModel
    }

    var body: some View {
        VStack(spacing: 0) {
            transcript
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }
            inputBar
        }
        .navigationTitle(viewModel.spec.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    Task {
                        await viewModel.unloadEngine() // free RAM before routing away
                        onSwitchModel()
                    }
                } label: {
                    Label("Models", systemImage: "chevron.backward")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.newConversation()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .disabled(viewModel.isGenerating || viewModel.messages.isEmpty)
            }
        }
        .task {
            await viewModel.loadEngine()
        }
        .overlay {
            loadingOverlay
        }
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.messages) { message in
                    MessageBubble(message: message,
                                  isStreaming: viewModel.isGenerating
                                      && message.id == viewModel.messages.last?.id)
                }
            }
            .padding()
        }
        .defaultScrollAnchor(.bottom)
    }

    // MARK: Input

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(viewModel.isGenerating || viewModel.loadState != .ready)
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
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || viewModel.loadState != .ready)
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

    // MARK: Load / error states

    @ViewBuilder
    private var loadingOverlay: some View {
        switch viewModel.loadState {
        case .loading:
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading model into memory…")
                        .font(.headline)
                    Text("This takes a few seconds the first time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .failed(let message):
            ContentUnavailableView {
                Label("Model Failed to Load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    Task { await viewModel.loadEngine() }
                }
                .buttonStyle(.borderedProminent)
                Button("Back to Models") {
                    Task {
                        await viewModel.unloadEngine()
                        onSwitchModel()
                    }
                }
            }
            .background(.background)

        case .ready:
            EmptyView()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(8)
            .background(.red)
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: ChatViewModel.DisplayMessage
    let isStreaming: Bool

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }

            Group {
                if message.text.isEmpty && isStreaming {
                    // Assistant is thinking — show a typing indicator until
                    // the first token arrives.
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 8)
                } else {
                    Text(message.text)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isUser ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.secondary),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(isUser ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))

            if !isUser { Spacer(minLength: 48) }
        }
    }
}
