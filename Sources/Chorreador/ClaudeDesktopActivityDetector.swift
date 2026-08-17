import Foundation

enum ClaudeDesktopActivityDetector {
    struct DesktopWorkers: Equatable {
        let resumedSessionIDs: Set<String>
        let hasWorkerWithoutSessionID: Bool
    }

    /// A fresh (non-resumed) desktop session's worker carries no session id in
    /// argv, so its transcript can only be found by recent write activity.
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
        guard !workers.resumedSessionIDs.isEmpty || workers.hasWorkerWithoutSessionID else {
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
            var shouldInspect = workers.resumedSessionIDs.contains(sessionID)

            if !shouldInspect, workers.hasWorkerWithoutSessionID {
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

            var foundSessionID = false
            for argument in rawLine.split(whereSeparator: { $0.isWhitespace }) {
                let prefix = "--resume="
                guard argument.hasPrefix(prefix) else { continue }
                let sessionID = argument.dropFirst(prefix.count)
                if !sessionID.isEmpty {
                    sessionIDs.insert(String(sessionID))
                    foundSessionID = true
                }
            }
            if !foundSessionID {
                hasWorkerWithoutSessionID = true
            }
        }
        return DesktopWorkers(
            resumedSessionIDs: sessionIDs,
            hasWorkerWithoutSessionID: hasWorkerWithoutSessionID
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
}
