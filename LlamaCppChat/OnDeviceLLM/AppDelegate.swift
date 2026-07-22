//
//  AppDelegate.swift
//  OnDeviceLLM
//
//  Created by Guntupalli, Bharath on 21/07/26.
//
//  Exists solely to receive background URLSession relaunch events. When a
//  model download finishes while the app is dead, iOS relaunches the app in
//  the background and calls handleEventsForBackgroundURLSession; recreating
//  the session (by touching the coordinator singleton) makes the queued
//  delegate callbacks replay, and the stored completion handler tells iOS
//  when we're done.
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == DownloadCoordinator.sessionIdentifier else {
            completionHandler()
            return
        }
        ModelDownloader.shared.setBackgroundCompletionHandler(completionHandler)
        // Touching .shared lazily recreates the session with the same
        // identifier, which triggers replay of the pending events.
        _ = DownloadCoordinator.shared
    }
}
