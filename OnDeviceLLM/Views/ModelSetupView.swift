//
//  ModelSetupView.swift
//  OnDeviceLLM
//
//  Created by Guntupalli, Bharath on 21/07/26.
//
//  Model picker + download manager. Each catalog model shows a control
//  matching its state: Download → progress + Pause → Resume → Start Chat.
//

import SwiftUI

struct ModelSetupView: View {
    /// Called when the user chooses a fully downloaded model to chat with.
    let onModelReady: (ModelSpec) -> Void

    private var downloader: ModelDownloader { ModelDownloader.shared }

    var body: some View {
        List {
            Section {
                ForEach(ModelCatalog.all) { spec in
                    ModelRow(spec: spec, onModelReady: onModelReady)
                }
            } header: {
                Text("Available Models")
            } footer: {
                Text("Models run fully on-device. Downloads continue in the background and are excluded from iCloud backup.")
            }
        }
        .navigationTitle("On-Device LLM")
        .onAppear {
            downloader.refreshFromDisk()
            DownloadCoordinator.shared.reattachToInFlightTasks()
        }
    }
}

private struct ModelRow: View {
    let spec: ModelSpec
    let onModelReady: (ModelSpec) -> Void

    private var downloader: ModelDownloader { ModelDownloader.shared }
    private var state: ModelDownloader.DownloadState { downloader.state(for: spec) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.displayName)
                        .font(.headline)
                    Text(ByteCountFormatter.string(fromByteCount: spec.approxSizeBytes,
                                                   countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                trailingControl
            }

            switch state {
            case .downloading(let progress):
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text("\(Int(progress * 100))% downloaded")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)

            default:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if case .downloaded = state {
                Button(role: .destructive) {
                    downloader.delete(spec)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch state {
        case .notDownloaded:
            Button("Download") { downloader.download(spec) }
                .buttonStyle(.borderedProminent)

        case .downloading:
            Button {
                downloader.pause(spec)
            } label: {
                Image(systemName: "pause.circle.fill")
                    .font(.title2)
            }

        case .paused:
            Button("Resume") { downloader.download(spec) }
                .buttonStyle(.bordered)

        case .downloaded:
            Button("Start Chat") { onModelReady(spec) }
                .buttonStyle(.borderedProminent)
                .tint(.green)

        case .failed:
            Button("Retry") { downloader.download(spec) }
                .buttonStyle(.bordered)
        }
    }
}

#Preview {
    NavigationStack {
        ModelSetupView { _ in }
    }
}
