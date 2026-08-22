import XCTest
@testable import Chorreador

final class PourJournalTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chorreador-journal-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("pour-journal.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        super.tearDown()
    }

    @MainActor
    func testCompletedPourRecordsDurationSourcesAndReason() {
        let journal = PourJournal(fileURL: fileURL)
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        journal.beginPour(at: start, sources: ["Claude Code"])
        journal.endPour(at: start.addingTimeInterval(3_600), reason: .finished)

        let record = try! XCTUnwrap(journal.lastCompletedRecord)
        XCTAssertEqual(record.sources, ["Claude Code"])
        XCTAssertEqual(record.endReason, .finished)
        XCTAssertEqual(record.duration(asOf: .distantFuture), 3_600)
        XCTAssertTrue(record.interruptions.isEmpty)
    }

    @MainActor
    func testSourcesMergeWithoutDuplicatesWhileOpen() {
        let journal = PourJournal(fileURL: fileURL)
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        journal.beginPour(at: start, sources: ["Claude Code"])
        journal.updateSources(["Claude Code", "hermes --provider"], at: start.addingTimeInterval(10))
        journal.updateSources(["hermes --provider"], at: start.addingTimeInterval(20))

        XCTAssertEqual(journal.openRecord?.sources, ["Claude Code", "hermes --provider"])
    }

    @MainActor
    func testInterruptionIsRecordedOnOpenPour() {
        let journal = PourJournal(fileURL: fileURL)
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        journal.beginPour(at: start, sources: ["scripts/clean-driver.sh"])
        journal.recordInterruption(
            sleptAt: start.addingTimeInterval(600),
            wokeAt: start.addingTimeInterval(900)
        )

        let record = try! XCTUnwrap(journal.openRecord)
        XCTAssertEqual(record.interruptions.count, 1)
        XCTAssertEqual(record.totalSleepLost, 300)
    }

    @MainActor
    func testDanglingRecordIsClosedAtLastAliveTimestampOnReload() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        do {
            let journal = PourJournal(fileURL: fileURL)
            journal.beginPour(at: start, sources: ["Manual pour"])
            journal.keepAlive(at: start.addingTimeInterval(1_800))
        }

        let reloaded = PourJournal(fileURL: fileURL)
        XCTAssertNil(reloaded.openRecord)
        let record = try! XCTUnwrap(reloaded.lastCompletedRecord)
        XCTAssertEqual(record.endReason, .appQuit)
        XCTAssertEqual(record.endedAt, start.addingTimeInterval(1_800))
    }

    @MainActor
    func testPersistenceRoundTripsThroughDisk() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        do {
            let journal = PourJournal(fileURL: fileURL)
            journal.beginPour(at: start, sources: ["Codex"])
            journal.recordInterruption(
                sleptAt: start.addingTimeInterval(60),
                wokeAt: start.addingTimeInterval(120)
            )
            journal.endPour(at: start.addingTimeInterval(600), reason: .batteryPause)
        }

        let reloaded = PourJournal(fileURL: fileURL)
        let record = try! XCTUnwrap(reloaded.lastCompletedRecord)
        XCTAssertEqual(record.sources, ["Codex"])
        XCTAssertEqual(record.endReason, .batteryPause)
        XCTAssertEqual(record.interruptions.count, 1)
    }

    @MainActor
    func testProtectedDurationSubtractsInterruptionsAndClampsToWindow() {
        let journal = PourJournal(fileURL: fileURL)
        let base = Date(timeIntervalSinceReferenceDate: 10_000)

        // One-hour pour with a 10-minute interruption in the middle.
        journal.beginPour(at: base, sources: ["Claude Code"])
        journal.recordInterruption(
            sleptAt: base.addingTimeInterval(1_200),
            wokeAt: base.addingTimeInterval(1_800)
        )
        journal.endPour(at: base.addingTimeInterval(3_600), reason: .finished)

        let full = journal.protectedDuration(
            from: base.addingTimeInterval(-86_400),
            to: base.addingTimeInterval(86_400)
        )
        XCTAssertEqual(full, 3_000)

        // A window covering only the first half sees the pre-interruption span
        // plus what fits before the window closes.
        let halfWindow = journal.protectedDuration(from: base, to: base.addingTimeInterval(1_500))
        XCTAssertEqual(halfWindow, 1_200)
    }

    @MainActor
    func testBeginningAPourClosesAForgottenOpenRecord() {
        let journal = PourJournal(fileURL: fileURL)
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        journal.beginPour(at: start, sources: ["Claude Code"])
        journal.beginPour(at: start.addingTimeInterval(100), sources: ["Codex"])

        XCTAssertEqual(journal.records.count, 2)
        XCTAssertEqual(journal.records.first?.endReason, .finished)
        XCTAssertEqual(journal.openRecord?.sources, ["Codex"])
    }

    @MainActor
    func testJournalPrunesToMaximumRecordCount() {
        let journal = PourJournal(fileURL: fileURL)
        let base = Date(timeIntervalSinceReferenceDate: 1_000)

        for index in 0..<70 {
            let start = base.addingTimeInterval(Double(index) * 100)
            journal.beginPour(at: start, sources: ["Claude Code"])
            journal.endPour(at: start.addingTimeInterval(50), reason: .finished)
        }

        XCTAssertEqual(journal.records.count, 60)
    }
}
