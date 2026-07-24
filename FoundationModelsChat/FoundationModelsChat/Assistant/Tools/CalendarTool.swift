//
//  CalendarTool.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Lets the model turn note action items into reminders or calendar
//  events. The `kind` argument uses .anyOf so constrained decoding can
//  only ever produce a valid value — no string-matching on tool input.
//

import Foundation
import FoundationModels

struct CalendarTool: Tool {
    let name = "addToCalendar"
    let description = "Creates a reminder or calendar event for the user. Use when the user asks to be reminded of something or to schedule something."

    let service: CalendarService

    @Generable
    struct Arguments {
        @Guide(description: "The reminder or event title")
        var title: String

        @Guide(description: "Whether to create a reminder or a calendar event", .anyOf(["reminder", "event"]))
        var kind: String

        @Guide(description: "Due date and time in ISO 8601 format, for example 2026-07-25T09:00:00")
        var dueDate: String
    }

    func call(arguments: Arguments) async throws -> String {
        let kind = CalendarService.ItemKind(rawValue: arguments.kind) ?? .reminder
        let due = Self.parseDate(arguments.dueDate)
        return try await service.create(kind: kind, title: arguments.title, due: due)
    }

    /// The model produces ISO-ish strings; fall back to tomorrow 9am when
    /// parsing fails rather than failing the whole tool call.
    private static func parseDate(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        if let date = formatter.date(from: string) { return date }

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
