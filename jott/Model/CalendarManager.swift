import EventKit
import Foundation
import SwiftUI
import Combine

@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    private let store = EKEventStore()
    @Published var isAuthorized = false

    private init() {
        let status = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = (status == .fullAccess)
    }

    func requestAccess() async {
        guard !isAuthorized else { return }
        do {
            let granted = try await store.requestFullAccessToEvents()
            isAuthorized = granted
        } catch { isAuthorized = false }
    }

    func upcomingEvents(days: Int = 7) -> [EKEvent] {
        guard isAuthorized else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: days, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    func importAsMeeting(_ event: EKEvent) -> Meeting {
        Meeting(
            title: event.title ?? "Untitled",
            participants: event.attendees?.compactMap { $0.name } ?? [],
            startTime: event.startDate,
            tags: []
        )
    }

    @discardableResult
    func createEvent(title: String, startDate: Date, durationMinutes: Int = 60,
                     recurrence: ParsedRecurrence? = nil) -> Bool {
        guard isAuthorized else { return false }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
        event.calendar = store.defaultCalendarForNewEvents
        if let rec = recurrence {
            event.recurrenceRules = [makeRecurrenceRule(rec)]
        }
        do {
            try store.save(event, span: .thisEvent)
            return true
        } catch {
            return false
        }
    }

    private func makeRecurrenceRule(_ rec: ParsedRecurrence) -> EKRecurrenceRule {
        let freq: EKRecurrenceFrequency
        switch rec.frequency {
        case .daily:   freq = .daily
        case .weekly:  freq = .weekly
        case .monthly: freq = .monthly
        case .yearly:  freq = .yearly
        }
        var daysOfWeek: [EKRecurrenceDayOfWeek]? = nil
        if rec.frequency == .weekly, let wd = rec.weekday,
           let ekDay = EKWeekday(rawValue: wd) {
            daysOfWeek = [EKRecurrenceDayOfWeek(ekDay)]
        }
        return EKRecurrenceRule(
            recurrenceWith: freq,
            interval: rec.interval,
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: nil,
            monthsOfTheYear: nil,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: nil
        )
    }
}
