import XCTest
@testable import jott

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    func testConsumeReturnsPendingTextWithinSixtySeconds() {
        let monitor = ClipboardMonitor.shared
        monitor.clear()
        monitor.seedPendingTextForTesting("clipboard value", copiedAt: Date().addingTimeInterval(-30))

        let consumed = monitor.consume()

        XCTAssertEqual(consumed, "clipboard value")
        XCTAssertNil(monitor.consume(), "consume() should clear pending text after first read")
    }

    func testConsumeDropsExpiredPendingText() {
        let monitor = ClipboardMonitor.shared
        monitor.clear()
        monitor.seedPendingTextForTesting("stale value", copiedAt: Date().addingTimeInterval(-61))

        let consumed = monitor.consume()

        XCTAssertNil(consumed)
        XCTAssertNil(monitor.consume())
    }
}
