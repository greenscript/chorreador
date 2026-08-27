import XCTest
@testable import Chorreador

final class CodexDesktopActivityDetectorTests: XCTestCase {
    func testReportsRunningForRecentAgentActivity() {
        XCTAssertTrue(
            CodexDesktopActivityDetector.isAgentRunning(activityQueryResult: "1\n")
        )
    }

    func testReportsIdleAfterTheActivityLeaseExpires() {
        XCTAssertFalse(
            CodexDesktopActivityDetector.isAgentRunning(activityQueryResult: "0\n")
        )
    }

    func testRejectsMalformedActivityResults() {
        XCTAssertFalse(
            CodexDesktopActivityDetector.isAgentRunning(activityQueryResult: "not-an-event")
        )
    }

    func testExtractsEveryRunningCodexAppServerPID() {
        let processList = """
          2466 /Applications/ChatGPT.app/Contents/Resources/codex app-server --listen stdio://
         57032 /Applications/ChatGPT.app/Contents/Resources/codex -c feature=true app-server
         93425 /Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node_repl
        """

        XCTAssertEqual(
            CodexDesktopActivityDetector.codexAppServerPIDs(in: processList),
            [2466, 57032]
        )
    }

    func testActivityQueryIncludesTurnStartAndWebsocketTargets() {
        let query = CodexDesktopActivityDetector.activityQuery(for: [44207])

        XCTAssertTrue(query.contains("codex_api::endpoint::responses_websocket"))
        XCTAssertTrue(query.contains("codex_core::responses_retry"))
        XCTAssertTrue(query.contains("app-server request: turn/%"))
        XCTAssertTrue(query.contains("%TurnInput%"))
        // Idle housekeeping must not hold the pour after a turn ends.
        XCTAssertFalse(query.contains("remoteControl/status"))
        XCTAssertFalse(query.contains("account/read"))
    }
}
