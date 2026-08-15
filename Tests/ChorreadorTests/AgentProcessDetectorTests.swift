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

    func testDetectsClaudeCodeLaunchedByClaudeDesktop() {
        let processList = """
          201 /Users/diego/Library/Application Support/Claude/claude-code/2.1.229/claude.app/Contents/MacOS/claude --output-format stream-json
        """

        XCTAssertEqual(AgentProcessDetector.detect(in: processList), [.claudeCode])
    }

    func testDetectsPackageBasedInstallations() {
        let processList = """
          301 node /opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/cli.js
          302 node /opt/homebrew/lib/node_modules/@openai/codex/bin/codex.js
        """

        XCTAssertEqual(AgentProcessDetector.detect(in: processList), [.claudeCode, .codex])
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
        """

        XCTAssertTrue(AgentProcessDetector.detect(in: processList).isEmpty)
    }
}
