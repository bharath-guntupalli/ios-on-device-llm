//
//  NoteSummary.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Structured "AI actions" output for a note. The @Generable macro also
//  synthesizes NoteSummary.PartiallyGenerated (every property optional),
//  which is what the streaming UI renders as fields fill in.
//

import Foundation
import FoundationModels

@Generable
struct NoteSummary {
    @Guide(description: "A punchy improved title for the note, at most 8 words")
    var suggestedTitle: String

    @Guide(description: "A 2 to 3 sentence summary of the note")
    var summary: String

    @Guide(description: "Concrete next steps implied by the note, phrased as imperatives", .count(3))
    var actionItems: [String]
}
