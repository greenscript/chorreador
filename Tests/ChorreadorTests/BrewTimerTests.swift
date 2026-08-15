import XCTest
@testable import Chorreador

final class BrewTimerTests: XCTestCase {
    func testTimerOptionsExposeExpectedDurations() {
        XCTAssertEqual(BrewTimerOption.thirtyMinutes.duration, 30 * 60)
        XCTAssertEqual(BrewTimerOption.oneHour.duration, 60 * 60)
        XCTAssertEqual(BrewTimerOption.twoHours.duration, 120 * 60)
    }
}
