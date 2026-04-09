import XCTest
@testable import jott

final class NaturalLanguageParserDateTests: XCTestCase {
    func testExtractAbsoluteDateMonthDayWithoutYear() {
        let parsed = NaturalLanguageParser.parseForEvent(from: "tax filing april 1")

        let comps = Calendar.current.dateComponents([.month, .day], from: parsed.date)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 1)
        XCTAssertTrue(parsed.hasExplicitDate)
    }

    func testExtractAbsoluteDateDayMonthWithYear() {
        let parsed = NaturalLanguageParser.parseForEvent(from: "renew passport 1 april 2027")

        let comps = Calendar.current.dateComponents([.year, .month, .day], from: parsed.date)
        XCTAssertEqual(comps.year, 2027)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 1)
        XCTAssertTrue(parsed.hasExplicitDate)
    }

    func testParseFallsBackToNoteWhenNoReminderOrMeetingIntent() {
        let result = NaturalLanguageParser.parse("Write product brief #strategy")

        guard case let .note(text, tags) = result else {
            return XCTFail("Expected note parse")
        }

        XCTAssertEqual(text, "Write product brief #strategy")
        XCTAssertEqual(tags, ["strategy"])
    }

    func testExtractRecurrenceEveryThreeDays() {
        let recurrence = NaturalLanguageParser.extractRecurrence(from: "backup photos every 3 days")
        XCTAssertEqual(recurrence, ParsedRecurrence(frequency: .daily, interval: 3, weekday: nil))
    }

    func testExtractRecurrenceEveryMonday() {
        let recurrence = NaturalLanguageParser.extractRecurrence(from: "status report every monday")
        XCTAssertEqual(recurrence, ParsedRecurrence(frequency: .weekly, interval: 1, weekday: 2))
    }

    func testChecklistRejectsLongPhrases() {
        let checklist = NaturalLanguageParser.detectChecklist("buy milk from nearby grocery store, eggs")
        XCTAssertNil(checklist)
    }
}
