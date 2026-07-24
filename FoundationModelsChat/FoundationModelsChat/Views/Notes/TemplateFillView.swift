//
//  TemplateFillView.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  The DynamicGenerationSchema showcase: the user names the fields at
//  runtime, the model fills them from the note, and constrained decoding
//  guarantees the result has exactly those fields.
//

import SwiftUI

struct TemplateFillView: View {
    @Environment(NotesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Bindable var note: Note

    @State private var template = NoteTemplate.starter
    @State private var results: [TemplateService.FilledField] = []
    @State private var isRunning = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Define the fields you want extracted from \"\(note.displayTitle)\". The schema is built at runtime with DynamicGenerationSchema.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Fields") {
                    ForEach($template.fields) { $field in
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Field name", text: $field.name)
                                .font(.subheadline.weight(.medium))
                                .autocorrectionDisabled()
                            TextField("What should the model extract?", text: $field.guide)
                                .font(.caption)
                        }
                    }
                    .onDelete { template.fields.remove(atOffsets: $0) }

                    Button {
                        template.fields.append(NoteTemplate.Field(name: "", guide: ""))
                    } label: {
                        Label("Add Field", systemImage: "plus")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if !results.isEmpty {
                    Section("Extracted") {
                        ForEach(results) { field in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(field.name)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(field.value)
                                    .font(.subheadline)
                            }
                        }
                        Button("Append to Note") {
                            let block = results
                                .map { "\($0.name): \($0.value)" }
                                .joined(separator: "\n")
                            note.body += "\n\n— \(template.name) —\n\(block)"
                            store.noteDidChange(note)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Fill Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isRunning {
                        ProgressView()
                    } else {
                        Button("Extract") { run() }
                            .disabled(validFields.isEmpty || note.body.count < 20)
                    }
                }
            }
        }
    }

    private var validFields: [NoteTemplate.Field] {
        template.fields.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func run() {
        isRunning = true
        errorMessage = nil
        results = []
        var cleaned = template
        cleaned.fields = validFields

        Task {
            do {
                results = try await TemplateService().fill(cleaned, from: note)
            } catch {
                errorMessage = FMErrorPresenter.message(for: error)
            }
            isRunning = false
        }
    }
}
