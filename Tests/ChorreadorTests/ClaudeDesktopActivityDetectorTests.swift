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

    func testFlagsWorkerLaunchedWithoutResumeArgument() {
        let processList = """
          7581 /Users/diego/Library/Application Support/Claude/claude-code/2.1.229/claude.app/Contents/MacOS/claude --input-format stream-json --model default
          7582 /Users/diego/Library/Application Support/Claude/claude-code/2.1.229/claude.app/Contents/MacOS/claude --input-format stream-json --resume=1804da6c-abfd-4caa-88ce-1d3e8d4d58e6
        """

        let workers = ClaudeDesktopActivityDetector.desktopWorkers(in: processList)
        XCTAssertEqual(workers.resumedSessionIDs, ["1804da6c-abfd-4caa-88ce-1d3e8d4d58e6"])
        XCTAssertTrue(workers.hasWorkerWithoutSessionID)
    }

    func testDetectsFreshSessionThroughRecentTranscriptActivity() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let transcript = """
        {"type":"assistant","message":{"stop_reason":"end_turn"}}
        {"type":"user","message":{"content":"continue"}}
        """
        try writeTranscript(transcript, sessionID: "fresh-session", home: home)

        let processList = """
          7581 /Users/diego/Library/Application Support/Claude/claude-code/2.1.229/claude.app/Contents/MacOS/claude --input-format stream-json --model default
        """

        XCTAssertTrue(
            ClaudeDesktopActivityDetector.isAgentRunning(
                in: processList,
                homeDirectory: home
            )
        )
        // The same transcript stops counting once it has been quiet for longer
        // than the recency window, so an abandoned turn cannot hold wake forever.
        XCTAssertFalse(
            ClaudeDesktopActivityDetector.isAgentRunning(
                in: processList,
                homeDirectory: home,
                now: Date().addingTimeInterval(
                    ClaudeDesktopActivityDetector.freshSessionRecencyWindow + 60
                )
            )
        )
    }

    func testResumedSessionDetectionIgnoresRecencyWindow() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let transcript = """
        {"type":"user","message":{"content":"build it"}}
        {"type":"assistant","message":{"stop_reason":"tool_use"}}
        """
        try writeTranscript(transcript, sessionID: "resumed-session", home: home)

        let processList = """
          7581 /Users/diego/Library/Application Support/Claude/claude-code/2.1.229/claude.app/Contents/MacOS/claude --input-format stream-json --resume=resumed-session
        """

        XCTAssertTrue(
            ClaudeDesktopActivityDetector.isAgentRunning(
                in: processList,
                homeDirectory: home,
                now: Date().addingTimeInterval(
                    ClaudeDesktopActivityDetector.freshSessionRecencyWindow + 60
                )
            )
        )
    }

    func testRecognizesIdleClaudeCodeCLIProcessWithoutTreatingItAsActive() {
        let processList = """
          60034 58085 claude
          60035 58085 /Users/diego/.local/bin/claude --model opus
        """

        let cli = ClaudeDesktopActivityDetector.cliProcesses(in: processList)
        XCTAssertTrue(cli.hasProcessWithoutSessionID)
        XCTAssertTrue(cli.resumedSessionIDs.isEmpty)
        XCTAssertTrue(
            ClaudeDesktopActivityDetector.isClaudeCLICommand("claude")
        )
        XCTAssertTrue(
            ClaudeDesktopActivityDetector.isClaudeCLICommand(
                "/users/diego/.local/bin/claude --model opus"
            )
        )
        XCTAssertFalse(
            ClaudeDesktopActivityDetector.isClaudeCLICommand(
                "/users/diego/library/application support/claude/claude-code/2.1.229/claude.app/contents/macos/claude --input-format stream-json"
            )
        )
    }

    func testIdleClaudeCodeCLIDoesNotActivateWithoutActiveTranscript() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let transcript = """
        {"type":"user","message":{"content":"hello"}}
        {"type":"assistant","message":{"stop_reason":"end_turn"}}
        {"type":"last-prompt"}
        """
        try writeTranscript(transcript, sessionID: "idle-cli-session", home: home)

        let processList = """
          60034 58085 claude
        """

        XCTAssertFalse(
            ClaudeDesktopActivityDetector.isAgentRunning(
                in: processList,
                homeDirectory: home
            )
        )
    }

    func testActiveClaudeCodeCLITurnKeepsWakeThroughRecentTranscript() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let transcript = """
        {"type":"user","message":{"content":"build it"}}
        {"type":"assistant","message":{"stop_reason":"tool_use"}}
        """
        try writeTranscript(transcript, sessionID: "active-cli-session", home: home)

        let processList = """
          60034 58085 /Users/diego/.local/bin/claude
        """

        XCTAssertTrue(
            ClaudeDesktopActivityDetector.isAgentRunning(
                in: processList,
                homeDirectory: home
            )
        )
        XCTAssertFalse(
            ClaudeDesktopActivityDetector.isAgentRunning(
                in: processList,
                homeDirectory: home,
                now: Date().addingTimeInterval(
                    ClaudeDesktopActivityDetector.freshSessionRecencyWindow + 60
                )
            )
        )
    }

    func testResumedClaudeCodeCLISessionIgnoresRecencyWindow() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let transcript = """
        {"type":"user","message":{"content":"continue"}}
        """
        try writeTranscript(transcript, sessionID: "cli-resumed-session", home: home)

        let processList = """
          60034 58085 claude --resume=cli-resumed-session
        """

        let cli = ClaudeDesktopActivityDetector.cliProcesses(in: processList)
        XCTAssertEqual(cli.resumedSessionIDs, ["cli-resumed-session"])
        XCTAssertFalse(cli.hasProcessWithoutSessionID)
        XCTAssertTrue(
            ClaudeDesktopActivityDetector.isAgentRunning(
                in: processList,
                homeDirectory: home,
                now: Date().addingTimeInterval(
                    ClaudeDesktopActivityDetector.freshSessionRecencyWindow + 60
                )
            )
        )
    }

    private func makeTemporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("chorreador-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func writeTranscript(_ contents: String, sessionID: String, home: URL) throws {
        let projectDir = home
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent("-Users-diego-code-example", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try contents.write(
            to: projectDir.appendingPathComponent("\(sessionID).jsonl"),
            atomically: true,
            encoding: .utf8
        )
    }
}
