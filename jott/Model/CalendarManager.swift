import EventKit
import Foundation
import SwiftUI
import Combine

@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    private let store = EKEventStore()
    @Published var isAuthorized = false
    @Published var isRemindersAuthorized = false

    // MARK: - Calendar/Reminders list selection (persisted)
    @Published var selectedCalendarId: String? = UserDefaults.standard.string(forKey: "jott_calendarId")
    @Published var selectedReminderListId: String? = UserDefaults.standard.string(forKey: "jott_reminderListId")

    var availableCalendars: [EKCalendar] {
        store.calendars(for: .event).filter { $0.allowsContentModifications }
    }
    var availableReminderLists: [EKCalendar] {
        store.calendars(for: .reminder).filter { $0.allowsContentModifications }
    }

    func selectCalendar(_ id: String?) {
        selectedCalendarId = id
        UserDefaults.standard.set(id, forKey: "jott_calendarId")
    }
    func selectReminderList(_ id: String?) {
        selectedReminderListId = id
        UserDefaults.standard.set(id, forKey: "jott_reminderListId")
    }

    private static func isGranted(_ status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14, *) { return status == .fullAccess }
        return status == .authorized
    }

    private init() {
        isAuthorized       = Self.isGranted(EKEventStore.authorizationStatus(for: .event))
        isRemindersAuthorized = Self.isGranted(EKEventStore.authorizationStatus(for: .reminder))
    }

    func requestAccess() async {
        guard !isAuthorized else { return }
        if #available(macOS 14, *) {
            do { isAuthorized = try await store.requestFullAccessToEvents() }
            catch { isAuthorized = false }
        } else {
            await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { [weak self] granted, _ in
                    Task { @MainActor [weak self] in
                        self?.isAuthorized = granted
                        cont.resume()
                    }
                }
            }
        }
    }

    func requestRemindersAccess() async {
        guard !isRemindersAuthorized else { return }
        if #available(macOS 14, *) {
            do { isRemindersAuthorized = try await store.requestFullAccessToReminders() }
            catch { isRemindersAuthorized = false }
        } else {
            await withCheckedContinuation { cont in
                store.requestAccess(to: .reminder) { [weak self] granted, _ in
                    Task { @MainActor [weak self] in
                        self?.isRemindersAuthorized = granted
                        cont.resume()
                    }
                }
            }
        }
    }

    @discardableResult
    func createReminder(title: String, dueDate: Date, recurrence: ParsedRecurrence? = nil) -> Bool {
        guard isRemindersAuthorized else { return false }
        let ekReminder = EKReminder(eventStore: store)
        ekReminder.title = title
        ekReminder.calendar = availableReminderLists.first { $0.calendarIdentifier == selectedReminderListId }
            ?? store.defaultCalendarForNewReminders()
        ekReminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: dueDate)
        ekReminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        if let rec = recurrence { ekReminder.recurrenceRules = [makeRecurrenceRule(rec)] }
        do { try store.save(ekReminder, commit: true); return true } catch { return false }
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
        event.calendar = availableCalendars.first { $0.calendarIdentifier == selectedCalendarId }
            ?? store.defaultCalendarForNewEvents
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
