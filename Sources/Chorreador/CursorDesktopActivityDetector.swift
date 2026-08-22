import Foundation

enum CursorDesktopActivityDetector {
    /// Cursor persists `unfinishedRunAt` when a composer turn starts and clears it
    /// when the turn finishes or is cleanly aborted. The timestamp is not refreshed
    /// during a long turn, so presence alone means "still in progress" — not age.
    /// A generous stale ceiling still drops crash leftovers that never cleared.
    static let unfinishedRunStaleCeiling: TimeInterval = 12 * 60 * 60

    private static let runningStatuses: Set<String> = [
        "generating",
        "streaming",
        "running",
        "pending",
        "in_progress"
    ]

    static func isAgentRunning(
        in processList: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date()
    ) -> Bool {
        guard isCursorDesktopOpen(in: processList) else { return false }

        if hasActiveAgentShell(in: processList) {
            return true
        }

        let databaseURL = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Cursor", isDirectory: true)
            .appendingPathComponent("User", isDirectory: true)
            .appendingPathComponent("globalStorage", isDirectory: true)
            .appendingPathComponent("state.vscdb")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return false }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", databaseURL.path, activityQuery]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let result = String(data: data, encoding: .utf8) else { return false }
            return isAgentRunning(composerDataRows: result, now: now)
        } catch {
            return false
        }
    }

    static func isCursorDesktopOpen(in processList: String) -> Bool {
        for command in commands(in: processList) {
            let lowercased = command.lowercased()
            if lowercased.contains("extension-host (agent-exec)") {
                return true
            }
            if executableNamed("cursor", in: lowercased)
                && lowercased.contains("/applications/cursor.app/contents/macos/cursor") {
                return true
            }
        }
        return false
    }

    static func hasActiveAgentShell(in processList: String) -> Bool {
        processList.lowercased().contains("__cursor_sandbox_env_restore")
    }

    static func isAgentRunning(composerDataRows: String, now: Date = Date()) -> Bool {
        for rawLine in composerDataRows.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if isAgentRunning(composerData: object, now: now) {
                return true
            }
        }
        return false
    }

    static func isAgentRunning(composerData: [String: Any], now: Date = Date()) -> Bool {
        if let status = composerData["status"] as? String,
           runningStatuses.contains(status) {
            return true
        }

        if let bubbleIDs = composerData["generatingBubbleIds"] as? [Any], !bubbleIDs.isEmpty {
            return true
        }

        if let unfinishedRunAt = unfinishedRunDate(from: composerData["unfinishedRunAt"]),
           now.timeIntervalSince(unfinishedRunAt) <= unfinishedRunStaleCeiling {
            return true
        }

        return false
    }

    private static let activityQuery = """
        SELECT value FROM cursorDiskKV
        WHERE key LIKE 'composerData:%'
          AND (
              value LIKE '%"unfinishedRunAt":%'
              OR value LIKE '%"generatingBubbleIds":["%'
              OR value LIKE '%"generatingBubbleIds":[{%'
              OR value LIKE '%"status":"generating"%'
              OR value LIKE '%"status":"streaming"%'
              OR value LIKE '%"status":"running"%'
              OR value LIKE '%"status":"pending"%'
              OR value LIKE '%"status":"in_progress"%'
          );
        """

    private static func unfinishedRunDate(from value: Any?) -> Date? {
        if let number = value as? Double {
            return Date(timeIntervalSince1970: number / 1000)
        }
        if let number = value as? Int {
            return Date(timeIntervalSince1970: Double(number) / 1000)
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue / 1000)
        }
        return nil
    }

    private static func commands(in processList: String) -> [String] {
        processList.split(separator: "\n").map { rawLine in
            rawLine
                .drop(while: { $0.isWhitespace || $0.isNumber })
                .trimmingCharacters(in: .whitespaces)
        }
    }

    private static func executableNamed(_ name: String, in command: String) -> Bool {
        guard let executable = command.split(whereSeparator: { $0.isWhitespace }).first else {
            return false
        }
        return executable == name || executable.hasSuffix("/\(name)")
    }
}
