//
//  TemplateService.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Builds a GenerationSchema at RUNTIME from user-defined fields and has
//  the model fill it from a note. Constrained decoding still applies:
//  the output is guaranteed to contain exactly these properties.
//

import Foundation
import FoundationModels

struct TemplateService {

    struct FilledField: Identifiable {
        let id = UUID()
        let name: String
        let value: String
    }

    /// Runs the note through a dynamically built schema and returns the
    /// extracted field values in template order.
    func fill(_ template: NoteTemplate, from note: Note) async throws -> [FilledField] {
        let properties = template.fields.map { field in
            DynamicGenerationSchema.Property(
                name: field.name,
                description: field.guide,
                schema: DynamicGenerationSchema(type: String.self)
            )
        }
        let root = DynamicGenerationSchema(
            name: template.name,
            properties: properties
        )
        let schema = try GenerationSchema(root: root, dependencies: [])

        let session = LanguageModelSession(
            instructions: "You extract structured information from personal notes. Extract only what the note actually says; use \"none\" when a field has no answer."
        )
        let response = try await session.respond(
            to: "Extract the template fields from this note:\n\nTitle: \(note.displayTitle)\n\n\(note.body)",
            schema: schema
        )

        let content = response.content
        return try template.fields.map { field in
            FilledField(name: field.name,
                        value: try content.value(String.self, forProperty: field.name))
        }
    }
}
