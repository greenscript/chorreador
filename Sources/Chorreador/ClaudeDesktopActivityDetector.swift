import Foundation

enum ClaudeDesktopActivityDetector {
    struct DesktopWorkers: Equatable {
        let resumedSessionIDs: Set<String>
        let hasWorkerWithoutSessionID: Bool
    }

    struct CLIProcesses: Equatable {
        let resumedSessionIDs: Set<String>
        let hasProcessWithoutSessionID: Bool
    }

    /// A fresh (non-resumed) session's process carries no session id in argv,
    /// so its transcript can only be found by recent write activity. This covers
    /// both Claude Desktop workers and an interactive Claude Code CLI.
    static let freshSessionRecencyWindow: TimeInterval = 600

    // Transcript lines with embedded screenshots have been observed above 600 KB;
    // a smaller window can contain no complete line and read as idle mid-turn.
    private static let transcriptTailWindow = 1_048_576

    static func isAgentRunning(
        in processList: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date()
    ) -> Bool {
        let workers = desktopWorkers(in: processList)
        let cli = cliProcesses(in: processList)
        let resumedSessionIDs = workers.resumedSessionIDs.union(cli.resumedSessionIDs)
        let scanRecentTranscripts = workers.hasWorkerWithoutSessionID
            || cli.hasProcessWithoutSessionID

        guard !resumedSessionIDs.isEmpty || scanRecentTranscripts else {
            return false
        }

        let projectsURL = homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            let sessionID = fileURL.deletingPathExtension().lastPathComponent
            var shouldInspect = resumedSessionIDs.contains(sessionID)

            if !shouldInspect, scanRecentTranscripts {
                let modified = try? fileURL
                    .resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate
                if let modified, now.timeIntervalSince(modified) <= freshSessionRecencyWindow {
                    shouldInspect = true
                }
            }

            if shouldInspect, isAgentRunning(transcriptTailAt: fileURL) {
                return true
            }
        }
        return false
    }

    static func desktopWorkers(in processList: String) -> DesktopWorkers {
        var sessionIDs: Set<String> = []
        var hasWorkerWithoutSessionID = false
        for rawLine in processList.split(separator: "\n") {
            let command = rawLine.lowercased()
            guard command.contains("/library/application support/claude/claude-code/"),
                  command.contains("/claude.app/contents/macos/claude") else { continue }

            if let sessionID = resumeSessionID(in: rawLine) {
                sessionIDs.insert(sessionID)
            } else {
                hasWorkerWithoutSessionID = true
            }
        }
        return DesktopWorkers(
            resumedSessionIDs: sessionIDs,
            hasWorkerWithoutSessionID: hasWorkerWithoutSessionID
        )
    }

    /// Interactive Claude Code CLI processes (not the Claude.app desktop shell,
    /// and not the embedded desktop worker under Application Support).
    static func cliProcesses(in processList: String) -> CLIProcesses {
        var sessionIDs: Set<String> = []
        var hasProcessWithoutSessionID = false
        for rawLine in processList.split(separator: "\n") {
            let command = command(from: rawLine).lowercased()
            guard isClaudeCLICommand(command) else { continue }

            if let sessionID = resumeSessionID(in: rawLine) {
                sessionIDs.insert(sessionID)
            } else {
                hasProcessWithoutSessionID = true
            }
        }
        return CLIProcesses(
            resumedSessionIDs: sessionIDs,
            hasProcessWithoutSessionID: hasProcessWithoutSessionID
        )
    }

    static func resumedSessionIDs(in processList: String) -> Set<String> {
        desktopWorkers(in: processList).resumedSessionIDs
    }

    static func isAgentRunning(transcriptTail: String) -> Bool {
        for rawLine in transcriptTail.split(separator: "\n").reversed() {
            guard let data = rawLine.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }

            if type == "user" {
                return true
            }
            if type == "assistant" {
                let message = event["message"] as? [String: Any]
                return message?["stop_reason"] as? String != "end_turn"
            }
        }
        return false
    }

    static func isClaudeCLICommand(_ command: String) -> Bool {
        if command.contains("/claude-code/")
            && command.contains("/claude.app/contents/macos/claude") {
            return false
        }

        guard !command.contains("/applications/claude.app/contents/") else { return false }

        return executableNamed("claude", in: command)
            || command.contains("@anthropic-ai/claude-code")
            || command.contains("/claude-code/cli.js")
    }

    private static func isAgentRunning(transcriptTailAt fileURL: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return false }
        defer { try? handle.close() }

        do {
            let fileSize = try handle.seekToEnd()
            let window = UInt64(transcriptTailWindow)
            let readStart = fileSize > window ? fileSize - window : 0
            try handle.seek(toOffset: readStart)
            guard let data = try handle.readToEnd(),
                  var tail = String(data: data, encoding: .utf8) else { return false }

            if readStart > 0, let firstNewline = tail.firstIndex(of: "\n") {
                tail.removeSubrange(...firstNewline)
            }
            return isAgentRunning(transcriptTail: tail)
        } catch {
            return false
        }
    }

    private static func resumeSessionID(in rawLine: Substring) -> String? {
        for argument in rawLine.split(whereSeparator: { $0.isWhitespace }) {
            let prefix = "--resume="
            guard argument.hasPrefix(prefix) else { continue }
            let sessionID = argument.dropFirst(prefix.count)
            if !sessionID.isEmpty {
                return String(sessionID)
            }
        }
        return nil
    }

    private static func command(from rawLine: Substring) -> String {
        rawLine
            .drop(while: { $0.isWhitespace || $0.isNumber })
            .trimmingCharacters(in: .whitespaces)
    }

    private static func executableNamed(_ name: String, in command: String) -> Bool {
        guard let executable = command.split(whereSeparator: { $0.isWhitespace }).first else {
            return false
        }
        return executable == name || executable.hasSuffix("/\(name)")
    }
}
