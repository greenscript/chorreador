import Foundation

enum ClaudeDesktopActivityDetector {
    static func isAgentRunning(
        in processList: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let sessionIDs = resumedSessionIDs(in: processList)
        guard !sessionIDs.isEmpty else { return false }

        let projectsURL = homeDirectory
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }

        for case let fileURL as URL in enumerator
        where fileURL.pathExtension == "jsonl"
            && sessionIDs.contains(fileURL.deletingPathExtension().lastPathComponent) {
            if isAgentRunning(transcriptTailAt: fileURL) {
                return true
            }
        }
        return false
    }

    static func resumedSessionIDs(in processList: String) -> Set<String> {
        var sessionIDs: Set<String> = []
        for rawLine in processList.split(separator: "\n") {
            let command = rawLine.lowercased()
            guard command.contains("/library/application support/claude/claude-code/"),
                  command.contains("/claude.app/contents/macos/claude") else { continue }

            for argument in rawLine.split(whereSeparator: { $0.isWhitespace }) {
                let prefix = "--resume="
                guard argument.hasPrefix(prefix) else { continue }
                let sessionID = argument.dropFirst(prefix.count)
                if !sessionID.isEmpty {
                    sessionIDs.insert(String(sessionID))
                }
            }
        }
        return sessionIDs
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
            let readStart = fileSize > 131_072 ? fileSize - 131_072 : 0
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
