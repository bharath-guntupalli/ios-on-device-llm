//
//  ModelDownloader.swift
//  OnDeviceLLM
//
//  Created by Guntupalli, Bharath on 21/07/26.
//
//  Two collaborating types:
//
//  - `DownloadCoordinator` (nonisolated): owns the background URLSession and
//    implements its delegate. Background sessions keep transferring while the
//    app is suspended — or even terminated by the system — and relaunch the
//    app when done, so this object must be reachable before any UI exists.
//
//  - `ModelDownloader` (@Observable, MainActor): the state SwiftUI observes.
//    The coordinator forwards events to it on the main actor.
//

import Foundation

// MARK: - Events from the URLSession delegate to the UI layer

nonisolated enum DownloadEvent: Sendable {
    case progress(specID: String, fraction: Double)
    case finished(specID: String)
    case failed(specID: String, message: String, resumable: Bool)
}

// MARK: - DownloadCoordinator

/// Owns the background URLSession. Nonisolated: delegate callbacks arrive on
/// the session's private serial queue, never on the main actor.
nonisolated final class DownloadCoordinator: NSObject, URLSessionDownloadDelegate {

    static let shared = DownloadCoordinator()
    static let sessionIdentifier = "BharathGuntupalli.OnDeviceLLM.modeldownload"

    /// Recreating a session with the same identifier after a relaunch is what
    /// makes iOS replay the queued delegate events — hence created in init on
    /// the singleton. nonisolated(unsafe): written exactly once during init,
    /// read-only afterwards.
    nonisolated(unsafe) private var session: URLSession!

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // Confined to the session's serial delegate queue — only delegate
    // callbacks touch it, so no lock is needed.
    nonisolated(unsafe) private var lastReportedProgress: [Int: Double] = [:]

    // MARK: Public API (called from the main actor)

    /// Start a fresh download for a model.
    func start(_ spec: ModelSpec) {
        let task = session.downloadTask(with: spec.downloadURL)
        // taskDescription survives process relaunch; an in-memory map would not.
        task.taskDescription = spec.id
        task.resume()
    }

    /// Cancel while keeping resume data so the transfer can pick up where it
    /// left off (Hugging Face supports HTTP Range requests).
    func pause(_ spec: ModelSpec) {
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription == spec.id {
                (task as? URLSessionDownloadTask)?.cancel { resumeData in
                    if let resumeData {
                        Self.persistResumeData(resumeData, for: spec.id)
                    }
                }
            }
        }
    }

    /// Resume from persisted resume data if we have any; returns false when a
    /// fresh `start` is needed instead.
    func resumeFromPersistedDataIfAvailable(_ spec: ModelSpec) -> Bool {
        guard let data = Self.loadResumeData(for: spec.id) else { return false }
        Self.deleteResumeData(for: spec.id)
        let task = session.downloadTask(withResumeData: data)
        task.taskDescription = spec.id
        task.resume()
        return true
    }

    func cancelDiscardingResumeData(_ spec: ModelSpec) {
        Self.deleteResumeData(for: spec.id)
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription == spec.id {
                task.cancel()
            }
        }
    }

    /// On launch, rebind any downloads that continued in nsurlsessiond while
    /// we were dead so the progress UI picks them back up.
    func reattachToInFlightTasks() {
        session.getAllTasks { tasks in
            for task in tasks {
                guard let specID = task.taskDescription, task.state == .running else { continue }
                let expected = task.countOfBytesExpectedToReceive
                let fraction = expected > 0
                    ? Double(task.countOfBytesReceived) / Double(expected)
                    : 0
                Self.dispatch(.progress(specID: specID, fraction: fraction))
            }
        }
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let specID = downloadTask.taskDescription else { return }

        // Fall back to the catalog's size estimate when the server doesn't
        // send Content-Length.
        var expected = totalBytesExpectedToWrite
        if expected == NSURLSessionTransferSizeUnknown {
            expected = ModelCatalog.spec(withID: specID)?.approxSizeBytes ?? 0
        }
        guard expected > 0 else { return }

        let fraction = min(1.0, Double(totalBytesWritten) / Double(expected))

        // Throttle: this callback fires very often; only bother the main
        // actor when progress moved visibly.
        let last = lastReportedProgress[downloadTask.taskIdentifier] ?? -1
        guard fraction - last >= 0.005 || fraction >= 1.0 else { return }
        lastReportedProgress[downloadTask.taskIdentifier] = fraction

        Self.dispatch(.progress(specID: specID, fraction: fraction))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let specID = downloadTask.taskDescription,
              let spec = ModelCatalog.spec(withID: specID) else { return }
        lastReportedProgress[downloadTask.taskIdentifier] = nil

        // Hugging Face serves an HTML error page (with a 4xx status) for bad
        // paths or rate limits — never accept those bytes as a model.
        if let http = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            Self.dispatch(.failed(specID: specID,
                                  message: "Server returned HTTP \(http.statusCode).",
                                  resumable: false))
            return
        }

        // The temp file at `location` is deleted the moment this method
        // returns, so the move must happen synchronously right here.
        do {
            let destination = spec.localURL
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)

            guard ModelSpec.hasGGUFMagic(at: destination) else {
                try? FileManager.default.removeItem(at: destination)
                Self.dispatch(.failed(specID: specID,
                                      message: "Downloaded file is not a valid GGUF model.",
                                      resumable: false))
                return
            }

            // Model weights are re-downloadable — keep them out of iCloud/iTunes
            // backups so a ~1GB file doesn't inflate the user's backup.
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = destination
            try mutableURL.setResourceValues(values)

            Self.deleteResumeData(for: specID)
            Self.dispatch(.finished(specID: specID))
        } catch {
            Self.dispatch(.failed(specID: specID,
                                  message: "Could not save model: \(error.localizedDescription)",
                                  resumable: false))
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        // nil error means success — didFinishDownloadingTo already handled it.
        guard let error, let specID = task.taskDescription else { return }
        lastReportedProgress[task.taskIdentifier] = nil

        let nsError = error as NSError

        // A user- or system-initiated pause also lands here; resume data (if
        // any) lets us continue later. Persist it and report a resumable stop.
        if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            Self.persistResumeData(resumeData, for: specID)
            Self.dispatch(.failed(specID: specID,
                                  message: nsError.code == NSURLErrorCancelled
                                      ? "Download paused."
                                      : nsError.localizedDescription,
                                  resumable: true))
            return
        }

        if nsError.code == NSURLErrorCancelled {
            // Deliberate cancel with no resume data — the UI already reflects it.
            return
        }

        Self.dispatch(.failed(specID: specID,
                              message: nsError.localizedDescription,
                              resumable: false))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // All replayed events are processed; tell the system we're done so it
        // can take our launch-image snapshot and re-suspend the app.
        Task { @MainActor in
            ModelDownloader.shared.fireBackgroundCompletionHandler()
        }
    }

    // MARK: Resume-data persistence (survives relaunch after force-quit)

    private static func resumeDataURL(for specID: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("ResumeData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(specID).resume")
    }

    private static func persistResumeData(_ data: Data, for specID: String) {
        try? data.write(to: resumeDataURL(for: specID), options: .atomic)
    }

    private static func loadResumeData(for specID: String) -> Data? {
        try? Data(contentsOf: resumeDataURL(for: specID))
    }

    static func deleteResumeData(for specID: String) {
        try? FileManager.default.removeItem(at: resumeDataURL(for: specID))
    }

    static func hasResumeData(for specID: String) -> Bool {
        FileManager.default.fileExists(atPath: resumeDataURL(for: specID).path)
    }

    /// Hop delegate-queue events onto the main actor for the observable.
    private static func dispatch(_ event: DownloadEvent) {
        Task { @MainActor in
            ModelDownloader.shared.apply(event)
        }
    }
}

// MARK: - ModelDownloader

/// UI-facing download state, one entry per catalog model.
@Observable
@MainActor
final class ModelDownloader {

    static let shared = ModelDownloader()

    enum DownloadState: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case paused(resumable: Bool)
        case downloaded
        case failed(message: String)
    }

    private(set) var states: [String: DownloadState] = [:]

    /// Stored by the AppDelegate when iOS relaunches us for background
    /// URLSession events; fired once the coordinator drains those events.
    private var backgroundCompletionHandler: (() -> Void)?

    private init() {
        refreshFromDisk()
    }

    func state(for spec: ModelSpec) -> DownloadState {
        states[spec.id] ?? .notDownloaded
    }

    /// Re-derive state from what's actually on disk (called on appear and
    /// after any operation that touches files).
    func refreshFromDisk() {
        for spec in ModelCatalog.all {
            switch states[spec.id] {
            case .downloading:
                continue // don't clobber a live transfer
            default:
                if spec.isDownloaded {
                    states[spec.id] = .downloaded
                } else if DownloadCoordinator.hasResumeData(for: spec.id) {
                    states[spec.id] = .paused(resumable: true)
                } else {
                    states[spec.id] = .notDownloaded
                }
            }
        }
    }

    func download(_ spec: ModelSpec) {
        guard hasEnoughDiskSpace(for: spec) else {
            states[spec.id] = .failed(message: "Not enough free storage. About \(ByteCountFormatter.string(fromByteCount: spec.approxSizeBytes, countStyle: .file)) is required.")
            return
        }
        states[spec.id] = .downloading(progress: 0)
        if !DownloadCoordinator.shared.resumeFromPersistedDataIfAvailable(spec) {
            DownloadCoordinator.shared.start(spec)
        }
    }

    func pause(_ spec: ModelSpec) {
        states[spec.id] = .paused(resumable: true)
        DownloadCoordinator.shared.pause(spec)
    }

    func cancel(_ spec: ModelSpec) {
        states[spec.id] = .notDownloaded
        DownloadCoordinator.shared.cancelDiscardingResumeData(spec)
    }

    func delete(_ spec: ModelSpec) {
        try? FileManager.default.removeItem(at: spec.localURL)
        DownloadCoordinator.deleteResumeData(for: spec.id)
        states[spec.id] = .notDownloaded
    }

    func apply(_ event: DownloadEvent) {
        switch event {
        case .progress(let specID, let fraction):
            // Ignore stale progress after a pause/cancel raced the callback.
            if case .downloading = states[specID] {
                states[specID] = .downloading(progress: fraction)
            } else if states[specID] == nil {
                states[specID] = .downloading(progress: fraction)
            }

        case .finished(let specID):
            states[specID] = .downloaded

        case .failed(let specID, let message, let resumable):
            if resumable, case .paused = states[specID] {
                // User-initiated pause — keep the paused state, not an error.
                return
            }
            states[specID] = resumable ? .paused(resumable: true) : .failed(message: message)
        }
    }

    // MARK: Background session completion handler

    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        backgroundCompletionHandler = handler
    }

    func fireBackgroundCompletionHandler() {
        backgroundCompletionHandler?()
        backgroundCompletionHandler = nil
    }

    // MARK: Disk preflight

    /// Require the model size plus headroom so the download can't fill the
    /// disk (which corrupts far more than this app).
    private func hasEnoughDiskSpace(for spec: ModelSpec) -> Bool {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let values = try? docs.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return true // can't determine — let the download try
        }
        return available > spec.approxSizeBytes + 200 * 1024 * 1024
    }
}
