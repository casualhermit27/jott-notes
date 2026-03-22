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
}
