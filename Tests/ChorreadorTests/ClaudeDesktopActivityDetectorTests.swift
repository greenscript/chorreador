import XCTest
@testable import Chorreador

final class ClaudeDesktopActivityDetectorTests: XCTestCase {
    func testExtractsEmbeddedClaudeDesktopSessionID() {
        let processList = """
          7581 /Users/diego/Library/Application Support/Claude/claude-code/2.1.229/claude.app/Contents/MacOS/claude --input-format stream-json --resume=1804da6c-abfd-4caa-88ce-1d3e8d4d58e6
        """

        XCTAssertEqual(
            ClaudeDesktopActivityDetector.resumedSessionIDs(in: processList),
            ["1804da6c-abfd-4caa-88ce-1d3e8d4d58e6"]
        )
    }

    func testReportsIdleAfterAssistantEndsTurn() {
        let transcript = """
        {"type":"user","message":{"content":"hello"}}
        {"type":"assistant","message":{"stop_reason":"end_turn"}}
        {"type":"last-prompt"}
        """

        XCTAssertFalse(ClaudeDesktopActivityDetector.isAgentRunning(transcriptTail: transcript))
    }

    func testReportsRunningAfterUserStartsTurn() {
        let transcript = """
        {"type":"assistant","message":{"stop_reason":"end_turn"}}
        {"type":"user","message":{"content":"continue"}}
        """

        XCTAssertTrue(ClaudeDesktopActivityDetector.isAgentRunning(transcriptTail: transcript))
    }

    func testReportsRunningDuringToolUse() {
        let transcript = """
        {"type":"user","message":{"content":"build it"}}
        {"type":"assistant","message":{"stop_reason":"tool_use"}}
        """

        XCTAssertTrue(ClaudeDesktopActivityDetector.isAgentRunning(transcriptTail: transcript))
    }
}
