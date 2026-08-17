import Foundation

enum CodingAgent: String, CaseIterable, Hashable, Sendable {
    case claudeCode
    case codex
    case cursor
    case openCode
    case t3Code

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .openCode: return "OpenCode"
        case .t3Code: return "T3 Code"
        }
    }
}

struct AgentDetectionResult: Equatable, Sendable {
    let agents: Set<CodingAgent>
    let customProcesses: Set<String>
}

enum AgentProcessDetector {
    static func runningDetection(customProcessNames: [String] = []) -> AgentDetectionResult {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return AgentDetectionResult(agents: [], customProcesses: [])
            }
            guard let processList = String(data: data, encoding: .utf8) else {
                return AgentDetectionResult(agents: [], customProcesses: [])
            }
            var agents = detect(in: processList)
            if CodexDesktopActivityDetector.isAgentRunning(in: processList) {
                agents.insert(.codex)
            }
            if ClaudeDesktopActivityDetector.isAgentRunning(in: processList) {
                agents.insert(.claudeCode)
            }

            return AgentDetectionResult(
                agents: agents,
                customProcesses: detectCustomProcesses(
                    in: processList,
                    matching: customProcessNames
                )
            )
        } catch {
            return AgentDetectionResult(agents: [], customProcesses: [])
        }
    }

    static func runningAgents() -> Set<CodingAgent> {
        runningDetection().agents
    }

    static func detect(in processList: String) -> Set<CodingAgent> {
        var detected: Set<CodingAgent> = []

        for rawLine in processList.split(separator: "\n") {
            let command = rawLine
                .drop(while: { $0.isWhitespace || $0.isNumber })
                .trimmingCharacters(in: .whitespaces)
            let lowercased = command.lowercased()

            if isClaudeCodeCommand(lowercased) {
                detected.insert(.claudeCode)
            }
            if isCodexCLICommand(lowercased) {
                detected.insert(.codex)
            }
            if isCursorAgentCommand(lowercased) {
                detected.insert(.cursor)
            }
            if isOpenCodeCommand(lowercased) {
                detected.insert(.openCode)
            }
            if isT3CodeCommand(lowercased) {
                detected.insert(.t3Code)
            }
        }

        return detected
    }

    // A plain entry matches an executable's basename. An entry containing "/" or
    // whitespace matches anywhere in the full command line, so interpreter-wrapped
    // jobs ("venv/bin/python3 …/hermes --provider … -z clean") stay detectable while
    // an idle daemon with the same binary but no job arguments does not.
    static func detectCustomProcesses(
        in processList: String,
        matching processNames: [String]
    ) -> Set<String> {
        var executableNames: [String: String] = [:]
        var commandPatterns: [String: String] = [:]
        for processName in processNames {
            let trimmed = processName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if trimmed.contains("/") || trimmed.contains(where: \.isWhitespace) {
                commandPatterns[trimmed.lowercased()] = trimmed
            } else {
                executableNames[trimmed.lowercased()] = trimmed
            }
        }
        guard !executableNames.isEmpty || !commandPatterns.isEmpty else { return [] }

        var detected: Set<String> = []
        for command in commands(in: processList) {
            let lowercased = command.lowercased()
            guard !lowercased.contains("/chorreador.app/contents/") else { continue }

            for (pattern, originalName) in commandPatterns where lowercased.contains(pattern) {
                detected.insert(originalName)
            }

            guard let executable = command.split(whereSeparator: { $0.isWhitespace }).first else {
                continue
            }

            let executableName = String(executable)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .split(separator: "/")
                .last
                .map(String.init)?
                .lowercased()

            if let executableName, let originalName = executableNames[executableName] {
                detected.insert(originalName)
            }
        }

        return detected
    }

    private static func commands(in processList: String) -> [String] {
        processList.split(separator: "\n").map { rawLine in
            rawLine
                .drop(while: { $0.isWhitespace || $0.isNumber })
                .trimmingCharacters(in: .whitespaces)
        }
    }

    private static func isClaudeCodeCommand(_ command: String) -> Bool {
        if command.contains("/claude-code/")
            && command.contains("/claude.app/contents/macos/claude") {
            return false
        }

        guard !command.contains("/applications/claude.app/contents/") else { return false }

        return executableNamed("claude", in: command)
            || command.contains("@anthropic-ai/claude-code")
            || command.contains("/claude-code/cli.js")
    }

    private static func isCodexCLICommand(_ command: String) -> Bool {
        let desktopPaths = [
            "/applications/codex.app/contents/",
            "/applications/chatgpt.app/contents/",
            "/library/application support/codex/",
            "/.codex/computer-use/",
            "/agentpresso.app/contents/",
            "/chorreador.app/contents/"
        ]
        guard !desktopPaths.contains(where: command.contains) else { return false }

        return executableNamed("codex", in: command)
            || command.contains("/codex-aarch64-apple-darwin")
            || command.contains("/codex-x86_64-apple-darwin")
            || command.contains("@openai/codex")
    }

    private static func isCursorAgentCommand(_ command: String) -> Bool {
        guard !command.contains("/applications/cursor.app/contents/") else { return false }

        return executableNamed("cursor-agent", in: command)
            || command.contains("/cursor-agent/versions/")
            || command.contains("/cursor-agent/bin/")
    }

    private static func isOpenCodeCommand(_ command: String) -> Bool {
        guard !command.contains("/applications/opencode.app/contents/macos/opencode") else {
            return false
        }

        return executableNamed("opencode", in: command)
            || command.contains("/opencode-darwin-arm64/bin/opencode")
            || command.contains("/opencode-darwin-x64/bin/opencode")
            || command.contains("/node_modules/opencode-ai/")
    }

    private static func isT3CodeCommand(_ command: String) -> Bool {
        if command.hasPrefix("/applications/t3 code.app/contents/macos/t3 code") {
            return true
        }

        return executableNamed("t3", in: command)
            || command.contains("npx t3@")
            || command.contains("npm exec t3@")
            || command.contains("/node_modules/t3/")
            || (command.contains("/t3 code.app/contents/resources/")
                && command.contains("server"))
    }

    private static func executableNamed(_ name: String, in command: String) -> Bool {
        guard let executable = command.split(whereSeparator: { $0.isWhitespace }).first else {
            return false
        }
        return executable == name || executable.hasSuffix("/\(name)")
    }
}
