//
//  NoteTags.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Guided-generation output for auto-tagging. Constrained decoding means
//  the model literally cannot produce anything but this shape — no JSON
//  parsing, no missing fields.
//

import Foundation
import FoundationModels

@Generable
struct NoteTags {
    @Guide(description: "Short, lowercase, single-word topical tags for the note", .count(4))
    var tags: [String]
}
