import Foundation

enum CodexDesktopActivityDetector {
    private static let activityLeaseSeconds = 5 * 60

    static func isAgentRunning(
        in processList: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let appServerPIDs = codexAppServerPIDs(in: processList)
        guard !appServerPIDs.isEmpty else { return false }

        let databaseURL = homeDirectory
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("logs_2.sqlite")
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return false }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", databaseURL.path, activityQuery(for: appServerPIDs)]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let result = String(data: data, encoding: .utf8) else { return false }
            return isAgentRunning(activityQueryResult: result)
        } catch {
            return false
        }
    }

    static func isAgentRunning(activityQueryResult: String) -> Bool {
        activityQueryResult.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    static func codexAppServerPIDs(in processList: String) -> [Int] {
        processList.split(separator: "\n").compactMap { rawLine in
            let fields = rawLine.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard fields.count == 2,
                  let pid = Int(fields[0]),
                  fields[1].lowercased().contains("/contents/resources/codex"),
                  fields[1].lowercased().contains(" app-server") else { return nil }
            return pid
        }
    }

    static func activityQuery(for appServerPIDs: [Int]) -> String {
        let processFilter = appServerPIDs
            .map { "process_uuid LIKE 'pid:\($0):%'" }
            .joined(separator: " OR ")

        return """
            SELECT CASE WHEN COALESCE(MAX(ts), 0)
                >= CAST(strftime('%s', 'now') AS INTEGER) - \(activityLeaseSeconds)
            THEN 1 ELSE 0 END
            FROM logs
            WHERE (\(processFilter))
              AND (
                  target IN (
                      'codex_core::stream_events_utils',
                      'codex_core::session::turn',
                      'codex_core::responses_retry',
                      'codex_api::sse::responses',
                      'codex_api::endpoint::responses_websocket'
                  )
                  OR (
                      target = 'codex_core::session::handlers'
                      AND feedback_log_body LIKE '%TurnInput%'
                  )
                  OR (
                      target = 'codex_app_server::outgoing_message'
                      AND (
                          feedback_log_body LIKE 'app-server event: item/%'
                          OR feedback_log_body LIKE 'app-server event: turn/diff/%'
                          OR feedback_log_body LIKE 'app-server event: thread/tokenUsage/%'
                      )
                  )
                  OR (
                      target = 'codex_app_server::message_processor'
                      AND feedback_log_body LIKE 'app-server request: turn/%'
                  )
              );
            """
    }
}
