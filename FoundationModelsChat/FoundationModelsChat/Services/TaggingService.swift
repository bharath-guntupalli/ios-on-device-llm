//
//  TaggingService.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Uses the specialized content-tagging variant of the system model —
//  SystemLanguageModel(useCase: .contentTagging) — rather than the general
//  model. Apple trains this use case specifically for topic extraction.
//

import Foundation
import FoundationModels

struct TaggingService {

    /// Generates topical tags for a note body. Returns [] when the model
    /// is unavailable or the text is too short to be worth tagging.
    func tags(for text: String) async -> [String] {
        let model = SystemLanguageModel(useCase: .contentTagging)
        guard model.isAvailable,
              text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 else {
            return []
        }

        let session = LanguageModelSession(model: model)
        do {
            let response = try await session.respond(
                to: "Tag the following note:\n\n\(text)",
                generating: NoteTags.self
            )
            return response.content.tags
                .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } catch {
            // Tagging is a background nicety — never surface its failures.
            return []
        }
    }
}
