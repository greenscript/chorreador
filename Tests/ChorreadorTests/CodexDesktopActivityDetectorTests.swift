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
}
