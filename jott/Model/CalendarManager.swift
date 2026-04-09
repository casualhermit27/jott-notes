import EventKit
import Foundation
import SwiftUI
import Combine
import AppKit

@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()
    private let store = EKEventStore()
    @Published var isAuthorized = false
    @Published var isRemindersAuthorized = false
    @Published var isRequestingCalendarAccess = false
    @Published var isRequestingRemindersAccess = false
    @Published var authorizationErrorMessage: String?

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
        if #available(macOS 14, *) { return status == .fullAccess || status == .writeOnly }
        // EKAuthorizationStatus.authorized is deprecated on macOS 14+, so use the pre-14 raw value.
        return status.rawValue == 3
    }

    private init() {
        isAuthorized       = Self.isGranted(EKEventStore.authorizationStatus(for: .event))
        isRemindersAuthorized = Self.isGranted(EKEventStore.authorizationStatus(for: .reminder))
    }

    func requestAccess() async {
        guard !isAuthorized else { return }
        Telemetry.addBreadcrumb("Requesting Calendar access", category: "calendar")
        isRequestingCalendarAccess = true
        defer { isRequestingCalendarAccess = false }
        if #available(macOS 14, *) {
            do {
                isAuthorized = try await store.requestFullAccessToEvents()
            } catch {
                isAuthorized = false
                Telemetry.captureError(error, context: "calendar.request_access")
            }
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
        if isAuthorized {
            authorizationErrorMessage = nil
            Telemetry.addBreadcrumb("Calendar access granted", category: "calendar")
        } else {
            authorizationErrorMessage = "Calendar access is denied. Open System Settings > Privacy & Security > Calendars."
            Telemetry.captureMessage("Calendar access denied", level: .warning)
        }
    }

    func requestRemindersAccess() async {
        guard !isRemindersAuthorized else { return }
        Telemetry.addBreadcrumb("Requesting Reminders access", category: "reminders")
        isRequestingRemindersAccess = true
        defer { isRequestingRemindersAccess = false }
        if #available(macOS 14, *) {
            do {
                isRemindersAuthorized = try await store.requestFullAccessToReminders()
            } catch {
                isRemindersAuthorized = false
                Telemetry.captureError(error, context: "reminders.request_access")
            }
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
        if isRemindersAuthorized {
            authorizationErrorMessage = nil
            Telemetry.addBreadcrumb("Reminders access granted", category: "reminders")
        } else {
            authorizationErrorMessage = "Reminders access is denied. Open System Settings > Privacy & Security > Reminders."
            Telemetry.captureMessage("Reminders access denied", level: .warning)
        }
    }

    @discardableResult
    func createReminder(title: String, dueDate: Date, recurrence: ParsedRecurrence? = nil) -> Bool {
        guard isRemindersAuthorized else { return false }
        Telemetry.addBreadcrumb(
            "Creating reminder",
            category: "reminders",
            data: ["has_recurrence": recurrence != nil]
        )
        let ekReminder = EKReminder(eventStore: store)
        ekReminder.title = title
        ekReminder.calendar = availableReminderLists.first { $0.calendarIdentifier == selectedReminderListId }
            ?? store.defaultCalendarForNewReminders()
        ekReminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: dueDate)
        ekReminder.addAlarm(EKAlarm(absoluteDate: dueDate))
        if let rec = recurrence { ekReminder.recurrenceRules = [makeRecurrenceRule(rec)] }
        do {
            try store.save(ekReminder, commit: true)
            Telemetry.addBreadcrumb("Reminder saved to EventKit", category: "reminders")
            return true
        } catch {
            Telemetry.captureError(error, context: "reminders.create")
            return false
        }
    }

    func upcomingEvents(days: Int = 7) -> [EKEvent] {
        guard isAuthorized else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: days, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        Telemetry.addBreadcrumb(
            "Fetched upcoming events",
            category: "calendar",
            data: ["count": events.count, "days": days]
        )
        return events
    }

    @discardableResult
    func createEvent(title: String, startDate: Date, durationMinutes: Int = 60,
                     recurrence: ParsedRecurrence? = nil) -> Bool {
        guard isAuthorized else { return false }
        Telemetry.addBreadcrumb(
            "Creating calendar event",
            category: "calendar",
            data: ["duration_minutes": durationMinutes, "has_recurrence": recurrence != nil]
        )
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
            Telemetry.addBreadcrumb("Calendar event saved to EventKit", category: "calendar")
            return true
        } catch {
            Telemetry.captureError(error, context: "calendar.create_event")
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

    func openCalendarPrivacySettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
    }

    func openRemindersPrivacySettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
    }

    private func openSystemSettingsPane(_ path: String) {
        guard let url = URL(string: path) else { return }
        NSWorkspace.shared.open(url)
    }
}
