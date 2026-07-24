//
//  NoteTemplate.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  A user-defined extraction template. Unlike @Generable (whose shape is
//  fixed at compile time), these fields exist only at runtime — which is
//  exactly what DynamicGenerationSchema is for.
//

import Foundation

struct NoteTemplate {
    struct Field: Identifiable {
        let id = UUID()
        var name: String
        var guide: String
    }

    var name: String
    var fields: [Field]

    static let starter = NoteTemplate(
        name: "MeetingNotes",
        fields: [
            Field(name: "attendees", guide: "People mentioned in the note"),
            Field(name: "decisions", guide: "Decisions that were made"),
            Field(name: "followUps", guide: "Open follow-up items"),
        ]
    )
}
