//
//  CalendarService.swift
//  FoundationModelsChat
//
//  Created by Guntupalli, Bharath on 24/07/26.
//
//  Thin EventKit wrapper used by CalendarTool. Access is requested lazily
//  on first use; usage strings live in the generated Info.plist keys.
//

import EventKit
import Foundation

final class CalendarService {

    enum ItemKind: String {
        case reminder, event
    }

    private let eventStore = EKEventStore()

    /// Creates a reminder or calendar event; returns a human confirmation
    /// that flows back to the model as tool output.
    func create(kind: ItemKind, title: String, due: Date) async throws -> String {
        switch kind {
        case .reminder:
            guard try await eventStore.requestFullAccessToReminders() else {
                return "The user has not granted Reminders access."
            }
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = title
            reminder.calendar = eventStore.defaultCalendarForNewReminders()
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due)
            try eventStore.save(reminder, commit: true)
            return "Created the reminder \"\(title)\" due \(due.formatted(date: .abbreviated, time: .shortened))."

        case .event:
            guard try await eventStore.requestFullAccessToEvents() else {
                return "The user has not granted Calendar access."
            }
            let event = EKEvent(eventStore: eventStore)
            event.title = title
            event.startDate = due
            event.endDate = due.addingTimeInterval(3600)
            event.calendar = eventStore.defaultCalendarForNewEvents
            try eventStore.save(event, span: .thisEvent, commit: true)
            return "Added the event \"\(title)\" on \(due.formatted(date: .abbreviated, time: .shortened))."
        }
    }
}
