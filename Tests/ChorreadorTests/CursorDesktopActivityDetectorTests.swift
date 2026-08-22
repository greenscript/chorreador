import XCTest
@testable import Chorreador

final class CursorDesktopActivityDetectorTests: XCTestCase {
    func testDetectsCursorDesktopViaAgentExecHost() {
        let processList = """
          5796 Cursor Helper (Plugin): extension-host (agent-exec) Chorreador [4-38]
          70945 /Applications/Cursor.app/Contents/MacOS/Cursor
        """

        XCTAssertTrue(CursorDesktopActivityDetector.isCursorDesktopOpen(in: processList))
    }

    func testDetectsCursorDesktopViaMainExecutable() {
        let processList = """
          70945 /Applications/Cursor.app/Contents/MacOS/Cursor
        """

        XCTAssertTrue(CursorDesktopActivityDetector.isCursorDesktopOpen(in: processList))
    }

    func testIgnoresIdleHelpersWithoutCursorDesktop() {
        let processList = """
          322 /Applications/Cursor.app/Contents/Frameworks/Cursor Helper.app/Contents/MacOS/Cursor Helper --type=renderer
          320 /Users/diego/.local/bin/cursor-agent -p Fix the tests
        """

        XCTAssertFalse(CursorDesktopActivityDetector.isCursorDesktopOpen(in: processList))
    }

    func testDetectsActiveSandboxShell() {
        let processList = """
          7714 /bin/zsh -c builtin eval "${__CURSOR_SANDBOX_ENV_RESTORE:-}"; dump_zsh_state >&4
        """

        XCTAssertTrue(CursorDesktopActivityDetector.hasActiveAgentShell(in: processList))
    }

    func testReportsRunningForUnfinishedComposerTurn() {
        let rows = """
        {"status":"aborted","generatingBubbleIds":[],"unfinishedRunAt":1787367508390,"isAgentic":true}
        """

        XCTAssertTrue(
            CursorDesktopActivityDetector.isAgentRunning(
                composerDataRows: rows,
                now: Date(timeIntervalSince1970: 1_787_367_508.390 + 600)
            )
        )
    }

    func testReportsRunningForGeneratingStatus() {
        let rows = """
        {"status":"generating","generatingBubbleIds":[],"isAgentic":true}
        """

        XCTAssertTrue(CursorDesktopActivityDetector.isAgentRunning(composerDataRows: rows))
    }

    func testReportsRunningForGeneratingBubbleIds() {
        let rows = """
        {"status":"none","generatingBubbleIds":["bubble-1"],"isAgentic":true}
        """

        XCTAssertTrue(CursorDesktopActivityDetector.isAgentRunning(composerDataRows: rows))
    }

    func testReportsIdleWhenComposerIsQuiet() {
        let rows = """
        {"status":"none","generatingBubbleIds":[],"isAgentic":true}
        {"status":"completed","generatingBubbleIds":[],"isAgentic":true}
        {"status":"aborted","generatingBubbleIds":[],"isAgentic":true}
        """

        XCTAssertFalse(CursorDesktopActivityDetector.isAgentRunning(composerDataRows: rows))
    }

    func testDropsStaleUnfinishedRunsAfterCeiling() {
        let startedAt = 1_787_367_508.390
        let rows = """
        {"status":"aborted","generatingBubbleIds":[],"unfinishedRunAt":\(Int(startedAt * 1000)),"isAgentic":true}
        """

        XCTAssertFalse(
            CursorDesktopActivityDetector.isAgentRunning(
                composerDataRows: rows,
                now: Date(timeIntervalSince1970: startedAt)
                    .addingTimeInterval(CursorDesktopActivityDetector.unfinishedRunStaleCeiling + 1)
            )
        )
    }

    func testRequiresCursorDesktopBeforeReadingComposerState() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        // Even with a composer row on disk, idle Macs without Cursor stay quiet.
        XCTAssertFalse(
            CursorDesktopActivityDetector.isAgentRunning(
                in: """
                  101 /opt/homebrew/bin/codex --full-auto
                """,
                homeDirectory: home
            )
        )
    }

    private func makeTemporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("chorreador-cursor-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }
}
