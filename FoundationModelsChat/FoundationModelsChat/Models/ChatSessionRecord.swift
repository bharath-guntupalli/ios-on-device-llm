//
//  ChatSessionRecord.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Persists the assistant conversation across launches: the framework
//  Transcript (to rebuild the session's model context) plus the display
//  messages (to rebuild the UI without parsing transcript segments).
//

import Foundation
import SwiftData

@Model
final class ChatSessionRecord {
    var transcriptData: Data
    var messagesData: Data
    var updatedAt: Date

    init(transcriptData: Data, messagesData: Data, updatedAt: Date = .now) {
        self.transcriptData = transcriptData
        self.messagesData = messagesData
        self.updatedAt = updatedAt
    }
}
