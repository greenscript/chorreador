import Foundation

enum KimiTurnActivity: Equatable {
    case active(at: Date?)
    case idle(at: Date?)

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var timestamp: Date? {
        switch self {
        case .active(let date), .idle(let date):
            return date
        }
    }
}

struct KimiWebInstance: Equatable {
    let pid: Int
    let startedAt: Date
    let heartbeatAt: Date
    let hostVersion: String?
}

enum KimiCodeWebActivityDetector {
    static let heartbeatStaleCeiling: TimeInterval = 60
    static let eventTailSearchLimit = 8 * 1024 * 1024

    private static let initialEventChunkSize = 8 * 1024
    private static let filenameSafeSessionIDCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "._-"))

    private static let activeLifecycleTypes: Set<String> = [
        "turn.started",
        "turn.step.started",
        "turn.step.completed",
        "tool.call.started",
        "tool.result"
    ]

    private static let idleLifecycleTypes: Set<String> = [
        "turn.ended",
        "prompt.completed",
        "turn.step.interrupted"
    ]

    static func isAgentRunning(
        in processList: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date(),
        workingDirectoriesByPID: [Int: URL]? = nil
    ) -> Bool {
        let kimiPIDs = kimiExecutablePIDs(in: processList)
        guard !kimiPIDs.isEmpty else { return false }

        let registrations = instanceRegistrations(at: instancesDirectory(in: homeDirectory))
        let liveCandidates = registrations.filter {
            isLiveInstance($0, kimiPIDs: kimiPIDs, now: now)
        }
        guard !liveCandidates.isEmpty else { return false }

        let cwdByPID = workingDirectoriesByPID
            ?? lookupWorkingDirectories(for: liveCandidates.map(\.pid))
        // cwd lookup only proves the process is still live; it is the launch
        // directory, not the workspace of every session the server can run.
        let validatedLive = liveCandidates.filter { cwdByPID[$0.pid] != nil }
        guard !validatedLive.isEmpty else { return false }

        return hasActiveSession(
            in: sessionsDirectory(in: homeDirectory),
            eventsDirectory: eventsDirectory(in: homeDirectory),
            registrations: registrations,
            liveInstances: validatedLive,
            now: now
        )
    }

    static func kimiExecutablePIDs(in processList: String) -> Set<Int> {
        var pids: Set<Int> = []
        for rawLine in processList.split(separator: "\n") {
            let fields = rawLine.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard fields.count == 2,
                  let pid = Int(fields[0]),
                  pid > 0,
                  executableNamed("kimi", in: String(fields[1])) else { continue }
            pids.insert(pid)
        }
        return pids
    }

    static func parseInstanceRecord(from data: Data) -> KimiWebInstance? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = intValue(object["pid"]),
              pid > 0,
              let startedAt = millisecondsDate(object["started_at"]),
              let heartbeatAt = millisecondsDate(object["heartbeat_at"]) else { return nil }
        return KimiWebInstance(
            pid: pid,
            startedAt: startedAt,
            heartbeatAt: heartbeatAt,
            hostVersion: object["host_version"] as? String
        )
    }

    static func isLiveInstance(
        _ instance: KimiWebInstance,
        kimiPIDs: Set<Int>,
        now: Date
    ) -> Bool {
        kimiPIDs.contains(instance.pid)
            && now.timeIntervalSince(instance.heartbeatAt) <= heartbeatStaleCeiling
    }

    static func parseWorkingDirectories(fromLsofOutput output: String) -> [Int: URL] {
        var result: [Int: URL] = [:]
        var currentPID: Int?
        var seeingCWD = false

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let marker = rawLine.first else { continue }
            let value = rawLine.dropFirst()
            switch marker {
            case "p":
                currentPID = Int(value)
                seeingCWD = false
            case "f":
                seeingCWD = value == "cwd"
            case "n":
                guard seeingCWD,
                      let pid = currentPID,
                      pid > 0,
                      !value.isEmpty else { continue }
                result[pid] = URL(fileURLWithPath: String(value))
            default:
                break
            }
        }

        return result
    }

    static func parseSessionState(from data: Data) -> (id: String, cwd: String)? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["id"] as? String,
              let cwd = object["cwd"] as? String else { return nil }
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCWD = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafeSessionID(trimmedID), !trimmedCWD.isEmpty else { return nil }
        return (trimmedID, trimmedCWD)
    }

    static func isSafeSessionID(_ id: String) -> Bool {
        guard !id.isEmpty, id != ".", id != ".." else { return false }
        return id.unicodeScalars.allSatisfy { filenameSafeSessionIDCharacters.contains($0) }
    }

    static func classifyLatestDecisiveEvent(in eventTail: String) -> KimiTurnActivity? {
        classifyLatestDecisiveEvent(in: Data(eventTail.utf8), startedMidLine: false)
    }

    static func latestTurnActivity(
        inEventFileAt fileURL: URL,
        searchLimit: Int = eventTailSearchLimit
    ) -> KimiTurnActivity? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        do {
            let fileSize = try handle.seekToEnd()
            guard fileSize > 0 else { return nil }

            let limit = UInt64(max(searchLimit, 0))
            guard limit > 0 else { return nil }

            var window = UInt64(initialEventChunkSize)
            while true {
                let readSize = min(window, fileSize, limit)
                let readStart = fileSize - readSize
                try handle.seek(toOffset: readStart)
                guard let data = try handle.read(upToCount: Int(readSize)) else { return nil }

                if let activity = classifyLatestDecisiveEvent(
                    in: data,
                    startedMidLine: readStart > 0
                ) {
                    return activity
                }

                if readSize >= fileSize || readSize >= limit {
                    return nil
                }
                window = min(max(window * 2, readSize + 1), limit, fileSize)
            }
        } catch {
            return nil
        }
    }

    static func attributedInstance(
        at timestamp: Date,
        registrations: [KimiWebInstance],
        liveInstances: [KimiWebInstance],
        now: Date
    ) -> KimiWebInstance? {
        registrations
            .filter {
                isLifetimeEligible(
                    $0,
                    event: timestamp,
                    isLive: liveInstances.contains($0),
                    now: now
                )
            }
            .max { $0.startedAt < $1.startedAt }
    }

    private static func isLifetimeEligible(
        _ instance: KimiWebInstance,
        event: Date,
        isLive: Bool,
        now: Date
    ) -> Bool {
        guard instance.startedAt <= event else { return false }
        if isLive {
            return event <= now
        }
        return event <= instance.heartbeatAt.addingTimeInterval(heartbeatStaleCeiling)
    }

    private static func instanceRegistrations(at directory: URL) -> [KimiWebInstance] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files.compactMap { fileURL in
            guard fileURL.pathExtension == "json",
                  let data = try? Data(contentsOf: fileURL) else { return nil }
            return parseInstanceRecord(from: data)
        }
    }

    private static func hasActiveSession(
        in sessionsDirectory: URL,
        eventsDirectory: URL,
        registrations: [KimiWebInstance],
        liveInstances: [KimiWebInstance],
        now: Date
    ) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return false }

        for case let fileURL as URL in enumerator where fileURL.lastPathComponent == "state.json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let session = parseSessionState(from: data) else { continue }

            let eventURL = eventsDirectory
                .appendingPathComponent(session.id)
                .appendingPathExtension("jsonl")
            if isActiveTurn(
                at: eventURL,
                registrations: registrations,
                liveInstances: liveInstances,
                now: now
            ) {
                return true
            }
        }
        return false
    }

    private static func isActiveTurn(
        at eventURL: URL,
        registrations: [KimiWebInstance],
        liveInstances: [KimiWebInstance],
        now: Date
    ) -> Bool {
        guard let activity = latestTurnActivity(inEventFileAt: eventURL),
              activity.isActive,
              let timestamp = activity.timestamp,
              let selected = attributedInstance(
                at: timestamp,
                registrations: registrations,
                liveInstances: liveInstances,
                now: now
              ) else { return false }
        return liveInstances.contains(selected)
    }

    private static func classifyLatestDecisiveEvent(
        in data: Data,
        startedMidLine: Bool
    ) -> KimiTurnActivity? {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return nil }

        if startedMidLine {
            lines.removeFirst()
        }
        if let last = data.last, last != UInt8(ascii: "\n"), !lines.isEmpty {
            lines.removeLast()
        }

        for line in lines.reversed() {
            var completeLine = Data(line)
            if completeLine.last == UInt8(ascii: "\r") {
                completeLine.removeLast()
            }
            guard !completeLine.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: completeLine) as? [String: Any],
                  let envelope = object["envelope"] as? [String: Any],
                  let type = envelope["type"] as? String else { continue }

            if type == "event.session.work_changed" {
                guard let payload = envelope["payload"] as? [String: Any],
                      let mainTurnActive = boolValue(payload["main_turn_active"]) else { continue }
                let timestamp = eventTimestamp(envelope["timestamp"])
                return mainTurnActive ? .active(at: timestamp) : .idle(at: timestamp)
            }

            if activeLifecycleTypes.contains(type) {
                return .active(at: eventTimestamp(envelope["timestamp"]))
            }
            if idleLifecycleTypes.contains(type) {
                return .idle(at: eventTimestamp(envelope["timestamp"]))
            }
        }
        return nil
    }

    private static func lookupWorkingDirectories(for pids: [Int]) -> [Int: URL] {
        let uniquePIDs = Array(Set(pids.filter { $0 > 0 })).sorted()
        guard !uniquePIDs.isEmpty else { return [:] }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = [
            "-a",
            "-p", uniquePIDs.map(String.init).joined(separator: ","),
            "-d", "cwd",
            "-Fn"
        ]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8) else { return [:] }
            return parseWorkingDirectories(fromLsofOutput: text)
        } catch {
            return [:]
        }
    }

    private static func instancesDirectory(in homeDirectory: URL) -> URL {
        kimiCodeRoot(in: homeDirectory)
            .appendingPathComponent("server", isDirectory: true)
            .appendingPathComponent("instances", isDirectory: true)
    }

    private static func eventsDirectory(in homeDirectory: URL) -> URL {
        kimiCodeRoot(in: homeDirectory)
            .appendingPathComponent("server", isDirectory: true)
            .appendingPathComponent("events", isDirectory: true)
    }

    private static func sessionsDirectory(in homeDirectory: URL) -> URL {
        kimiCodeRoot(in: homeDirectory)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private static func kimiCodeRoot(in homeDirectory: URL) -> URL {
        homeDirectory.appendingPathComponent(".kimi-code", isDirectory: true)
    }

    private static func executableNamed(_ name: String, in command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard let executable = trimmed.split(whereSeparator: { $0.isWhitespace }).first else {
            return false
        }
        return executable == name || executable.hasSuffix("/\(name)")
    }

    private static func eventTimestamp(_ value: Any?) -> Date? {
        guard let raw = value as? String else { return nil }

        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) {
            return date
        }

        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: raw)
    }

    private static func millisecondsDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue / 1000)
        }
        if let int = value as? Int {
            return Date(timeIntervalSince1970: Double(int) / 1000)
        }
        if let double = value as? Double {
            return Date(timeIntervalSince1970: double / 1000)
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        return nil
    }
}
