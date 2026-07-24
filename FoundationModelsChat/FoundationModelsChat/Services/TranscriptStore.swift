//
//  TranscriptStore.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Saves and restores the assistant conversation. Transcript is Codable,
//  so a session can be rebuilt with LanguageModelSession(transcript:) —
//  the model regains its full conversational context after a relaunch.
//

import Foundation
import FoundationModels
import SwiftData

struct TranscriptStore {

    let context: ModelContext

    struct Saved {
        let transcript: Transcript
        let messages: [AssistantViewModel.DisplayMessage]
    }

    func save(transcript: Transcript, messages: [AssistantViewModel.DisplayMessage]) {
        do {
            let transcriptData = try JSONEncoder().encode(transcript)
            let messagesData = try JSONEncoder().encode(messages)

            if let record = existingRecord() {
                record.transcriptData = transcriptData
                record.messagesData = messagesData
                record.updatedAt = .now
            } else {
                context.insert(ChatSessionRecord(transcriptData: transcriptData,
                                                 messagesData: messagesData))
            }
            try context.save()
        } catch {
            print("Transcript save failed: \(error.localizedDescription)")
        }
    }

    func load() -> Saved? {
        guard let record = existingRecord() else { return nil }
        do {
            let transcript = try JSONDecoder().decode(Transcript.self,
                                                      from: record.transcriptData)
            let messages = try JSONDecoder().decode([AssistantViewModel.DisplayMessage].self,
                                                    from: record.messagesData)
            guard !messages.isEmpty else { return nil }
            return Saved(transcript: transcript, messages: messages)
        } catch {
            return nil
        }
    }

    func clear() {
        if let record = existingRecord() {
            context.delete(record)
            try? context.save()
        }
    }

    private func existingRecord() -> ChatSessionRecord? {
        var descriptor = FetchDescriptor<ChatSessionRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }
}
