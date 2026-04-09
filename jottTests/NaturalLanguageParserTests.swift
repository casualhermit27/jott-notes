import XCTest
@testable import jott

final class NaturalLanguageParserTests: XCTestCase {
    func testParseReminderExtractsIntentAndTags() {
        let result = NaturalLanguageParser.parse("Remind me to submit report tomorrow at 3pm #work")

        guard case let .reminder(text, dueDate, tags) = result else {
            return XCTFail("Expected reminder parse")
        }

        XCTAssertTrue(text.lowercased().contains("submit report"))
        XCTAssertEqual(tags, ["work"])
        XCTAssertGreaterThan(dueDate.timeIntervalSinceNow, 0)
    }

    func testParseMeetingExtractsParticipantsFromWithAndMentions() {
        let result = NaturalLanguageParser.parse("Meeting with Alex and @sam tomorrow at 10am #planning")

        guard case let .meeting(title, participants, _, tags) = result else {
            return XCTFail("Expected meeting parse")
        }

        XCTAssertFalse(title.isEmpty)
        XCTAssertTrue(participants.contains("Alex"))
        XCTAssertTrue(participants.contains("sam"))
        XCTAssertEqual(tags, ["planning"])
    }

    func testExtractDateTomorrowIsApproximatelyOneDayAhead() {
        guard let date = NaturalLanguageParser.extractDate(from: "tomorrow") else {
            return XCTFail("Expected date for tomorrow")
        }

        let seconds = date.timeIntervalSinceNow
        XCTAssertGreaterThan(seconds, 20 * 60 * 60)
        XCTAssertLessThan(seconds, 28 * 60 * 60)
    }

    func testExtractTimeParsesTwelveHourClock() {
        let calendar = Calendar.current
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        guard let parsed = NaturalLanguageParser.extractTime(from: "at 3:45pm", baseDate: base) else {
            return XCTFail("Expected parsed time")
        }

        let components = calendar.dateComponents([.hour, .minute], from: parsed)
        XCTAssertEqual(components.hour, 15)
        XCTAssertEqual(components.minute, 45)
    }

    func testRemoveDateReferencesStripsCommonDateTokens() {
        let cleaned = NaturalLanguageParser.removeDateReferences(from: "submit report tomorrow at 3pm")
        XCTAssertEqual(cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }, ["submit", "report", "at"])
    }

    func testExtractRecurrenceParsesEveryOtherWeek() {
        let recurrence = NaturalLanguageParser.extractRecurrence(from: "pay rent every other week")
        XCTAssertEqual(recurrence, ParsedRecurrence(frequency: .weekly, interval: 2, weekday: nil))
    }

    func testDetectChecklistRecognizesCommaSeparatedItems() {
        let items = NaturalLanguageParser.detectChecklist("milk, eggs, bread")
        XCTAssertEqual(items, ["milk", "eggs", "bread"])
    }

    func testParseForEventUsesExplicitDayAndTime() {
        let parsed = NaturalLanguageParser.parseForEvent(from: "Team sync tomorrow at 9am")

        XCTAssertEqual(formattedHourMinute(parsed.date, calendar: .current), "09:00")
        XCTAssertTrue(parsed.hasExplicitDate)
        XCTAssertFalse(parsed.title.isEmpty)
    }
}

private func formattedHourMinute(_ date: Date, calendar: Calendar) -> String {
    let comps = calendar.dateComponents([.hour, .minute], from: date)
    let hour = String(format: "%02d", comps.hour ?? 0)
    let minute = String(format: "%02d", comps.minute ?? 0)
    return "\(hour):\(minute)"
}
