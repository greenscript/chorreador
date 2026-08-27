import XCTest
@testable import Chorreador

final class AgentProcessDetectorTests: XCTestCase {
    func testDetectsCLIProcessesAndExcludesDesktopHelpers() {
        let processList = """
          101 /opt/homebrew/bin/codex --full-auto
          102 /Users/diego/.local/bin/claude --model opus
          103 /Applications/Codex.app/Contents/MacOS/Codex
          104 /Applications/Codex.app/Contents/Frameworks/Codex Helper.app/Contents/MacOS/Codex Helper --type=renderer
          105 /Applications/Claude.app/Contents/MacOS/Claude
          106 /Applications/Claude.app/Contents/Frameworks/Claude Helper.app/Contents/MacOS/Claude Helper
        """

        XCTAssertEqual(AgentProcessDetector.detect(in: processList), [.claudeCode, .codex])
    }

    func testIgnoresPersistentClaudeCodeWorkerLaunchedByClaudeDesktop() {
        let processList = """
          201 /Users/diego/Library/Application Support/Claude/claude-code/2.1.229/claude.app/Contents/MacOS/claude --output-format stream-json
        """

        XCTAssertTrue(AgentProcessDetector.detect(in: processList).isEmpty)
    }

    func testDetectsPackageBasedInstallations() {
        let processList = """
          301 node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js
          302 node /opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js
        """

        XCTAssertEqual(AgentProcessDetector.detect(in: processList), [.claudeCode, .codex])
    }

    func testIgnoresPersistentCodexDesktopWorkers() {
        let processList = """
          304 /Applications/ChatGPT.app/Contents/Resources/codex sandbox -c shell_environment_policy.inherit=all
          305 /Applications/Codex.app/Contents/Resources/codex exec --full-auto Build the feature
          306 /Applications/ChatGPT.app/Contents/Resources/codex app-server --listen stdio://
        """

        XCTAssertTrue(AgentProcessDetector.detect(in: processList).isEmpty)
    }

    func testDetectsOpenCodeInstallations() {
        let processList = """
          310 /Users/diego/.opencode/bin/opencode run Build the feature
          311 /opt/homebrew/bin/node /opt/homebrew/lib/node_modules/opencode-ai/bin/opencode
        """

        XCTAssertEqual(AgentProcessDetector.detect(in: processList), [.openCode])
    }

    func testDetectsCursorAgentWithoutDetectingCursorEditor() {
        let processList = """
          320 /Users/diego/.local/bin/cursor-agent -p Fix the tests
          321 /Applications/Cursor.app/Contents/MacOS/Cursor
          322 /Applications/Cursor.app/Contents/Frameworks/Cursor Helper.app/Contents/MacOS/Cursor Helper --type=renderer
        """

        XCTAssertEqual(AgentProcessDetector.detect(in: processList), [.cursor])
    }

    func testDetectsT3CodeDesktopAndCLI() {
        let processList = """
          330 /Applications/T3 Code.app/Contents/MacOS/T3 Code
          331 /opt/homebrew/bin/node /Users/diego/.npm/_npx/cache/node_modules/t3/dist/bin.js
          332 npm exec t3@latest
        """

        XCTAssertEqual(AgentProcessDetector.detect(in: processList), [.t3Code])
    }

    func testIgnoresBrandedDesktopProcesses() {
        let processList = """
          401 /Applications/ChatGPT.app/Contents/Resources/codex-code-mode-host
          402 /Applications/Claude.app/Contents/Frameworks/Electron Framework.framework/Helpers/chrome_crashpad_handler --database=Claude
          403 /Users/diego/.codex/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService
          404 /Applications/OpenCode.app/Contents/MacOS/opencode
          405 /Applications/ChatGPT.app/Contents/Resources/codex app-server --listen stdio://
        """

        XCTAssertTrue(AgentProcessDetector.detect(in: processList).isEmpty)
    }

    func testDetectsCustomExecutableNamesWithoutPartialMatches() {
        let processList = """
          501 /opt/homebrew/bin/aider --model sonnet
          502 /Users/diego/bin/aider-helper --watch
          503 /usr/local/bin/goose session
        """

        XCTAssertEqual(
            AgentProcessDetector.detectCustomProcesses(
                in: processList,
                matching: ["aider", "goose"]
            ),
            ["aider", "goose"]
        )
    }

    func testCommandLinePatternsMatchInterpreterWrappedJobs() {
        let processList = """
          701 /Users/diego/.hermes/hermes-agent/venv/bin/python3 /Users/diego/.hermes/hermes-agent/venv/bin/hermes --provider deepseek -m deepseek-chat -z clean tomas-4
          702 bash scripts/clean-driver.sh
          703 node /opt/homebrew/bin/tsx rag/ingest-incremental.ts
        """

        XCTAssertEqual(
            AgentProcessDetector.detectCustomProcesses(
                in: processList,
                matching: ["hermes --provider", "scripts/clean-driver.sh", "rag/ingest-incremental.ts"]
            ),
            ["hermes --provider", "scripts/clean-driver.sh", "rag/ingest-incremental.ts"]
        )
    }

    func testCommandLinePatternsIgnoreIdleDaemonAndDesktopApp() {
        let processList = """
          711 /Users/diego/.hermes/hermes-agent/venv/bin/python3 /Users/diego/.hermes/hermes-agent/venv/bin/hermes
          712 /Applications/Hermes.app/Contents/MacOS/Hermes
        """

        XCTAssertTrue(
            AgentProcessDetector.detectCustomProcesses(
                in: processList,
                matching: ["hermes --provider", "-z clean"]
            ).isEmpty
        )
    }

    func testCommandLinePatternsMatchCaseInsensitively() {
        let processList = """
          721 bash /Users/diego/Projects/Scripts/Clean-Driver.sh
        """

        XCTAssertEqual(
            AgentProcessDetector.detectCustomProcesses(
                in: processList,
                matching: ["scripts/clean-driver.sh"]
            ),
            ["scripts/clean-driver.sh"]
        )
    }

    func testCommandLinePatternsStillIgnoreChorreadorItself() {
        let processList = """
          731 /Applications/Chorreador.app/Contents/MacOS/Chorreador
        """

        XCTAssertTrue(
            AgentProcessDetector.detectCustomProcesses(
                in: processList,
                matching: ["contents/macos"]
            ).isEmpty
        )
    }

    func testCustomDetectionIgnoresChorreadorItself() {
        let processList = """
          601 /Applications/Chorreador.app/Contents/MacOS/Chorreador
        """

        XCTAssertTrue(
            AgentProcessDetector.detectCustomProcesses(
                in: processList,
                matching: ["Chorreador"]
            ).isEmpty
        )
    }

    func testBareKimiProcessIsNotDetectedByGenericMatching() {
        let processList = """
          3407 kimi
          70539 /opt/homebrew/bin/kimi
          88001 /usr/local/bin/kimi web
        """

        XCTAssertTrue(AgentProcessDetector.detect(in: processList).isEmpty)
    }

    func testKimiCodeBuiltInAgentUsesVisibleSourceName() {
        XCTAssertEqual(CodingAgent.kimiCode.displayName, "Kimi Code")
        XCTAssertTrue(CodingAgent.allCases.contains(.kimiCode))
    }
}
