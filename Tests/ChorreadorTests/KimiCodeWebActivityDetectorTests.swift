import XCTest
@testable import Chorreador

final class KimiCodeWebActivityDetectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_796_000)

    func testParsesMultipleLiveInstanceRecordsAndAcceptsExactKimiPIDs() {
        let first = instanceJSON(pid: 3407, startedAt: now.addingTimeInterval(-90), heartbeatAt: now.addingTimeInterval(-3), version: "0.36.1")
        let second = instanceJSON(pid: 70539, startedAt: now.addingTimeInterval(-3600), heartbeatAt: now.addingTimeInterval(-1), version: "0.30.0")

        let parsed = [first, second].compactMap { KimiCodeWebActivityDetector.parseInstanceRecord(from: $0) }
        XCTAssertEqual(parsed.map(\.pid), [3407, 70539])
        XCTAssertEqual(parsed.map(\.hostVersion), ["0.36.1", "0.30.0"])

        let processList = """
          3407 /opt/homebrew/bin/kimi
         70539 kimi
         88001 /usr/bin/python3
        """
        let kimiPIDs = KimiCodeWebActivityDetector.kimiExecutablePIDs(in: processList)
        XCTAssertEqual(kimiPIDs, [3407, 70539])

        XCTAssertTrue(
            parsed.allSatisfy {
                KimiCodeWebActivityDetector.isLiveInstance($0, kimiPIDs: kimiPIDs, now: now)
            }
        )
    }

    func testRejectsStaleHeartbeatMissingPIDReusedPIDMalformedJSONAndMissingCWD() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let livePID = 3407
        let reusedPID = 88001
        let missingPID = 4242

        try writeInstance(
            pid: livePID,
            startedAt: now.addingTimeInterval(-30),
            heartbeatAt: now.addingTimeInterval(-KimiCodeWebActivityDetector.heartbeatStaleCeiling - 1),
            home: home,
            name: "stale"
        )
        try writeInstance(
            pid: missingPID,
            startedAt: now.addingTimeInterval(-30),
            heartbeatAt: now.addingTimeInterval(-2),
            home: home,
            name: "missing-pid"
        )
        try writeInstance(
            pid: reusedPID,
            startedAt: now.addingTimeInterval(-30),
            heartbeatAt: now.addingTimeInterval(-2),
            home: home,
            name: "reused"
        )
        try writeRawInstance("{not-json", home: home, name: "malformed")
        try writeInstance(
            pid: 5500,
            startedAt: now.addingTimeInterval(-30),
            heartbeatAt: now.addingTimeInterval(-2),
            home: home,
            name: "no-cwd"
        )

        let processList = """
          3407 /opt/homebrew/bin/kimi
          5500 kimi
         88001 /usr/bin/python3 -m http.server
        """

        XCTAssertNil(KimiCodeWebActivityDetector.parseInstanceRecord(from: Data("{not-json".utf8)))
        XCTAssertFalse(
            KimiCodeWebActivityDetector.isAgentRunning(
                in: processList,
                homeDirectory: home,
                now: now,
                workingDirectoriesByPID: [:]
            )
        )

        let stale = KimiCodeWebActivityDetector.parseInstanceRecord(
            from: instanceJSON(
                pid: 3407,
                startedAt: now.addingTimeInterval(-30),
                heartbeatAt: now.addingTimeInterval(-KimiCodeWebActivityDetector.heartbeatStaleCeiling - 1)
            )
        )!
        let kimiPIDs: Set<Int> = [3407, 5500]
        XCTAssertFalse(
            KimiCodeWebActivityDetector.isLiveInstance(stale, kimiPIDs: kimiPIDs, now: now)
        )
        XCTAssertFalse(
            KimiCodeWebActivityDetector.isLiveInstance(
                KimiWebInstance(
                    pid: 4242,
                    startedAt: now.addingTimeInterval(-30),
                    heartbeatAt: now.addingTimeInterval(-2),
                    hostVersion: nil
                ),
                kimiPIDs: kimiPIDs,
                now: now
            )
        )
        XCTAssertFalse(
            KimiCodeWebActivityDetector.isLiveInstance(
                KimiWebInstance(
                    pid: 88001,
                    startedAt: now.addingTimeInterval(-30),
                    heartbeatAt: now.addingTimeInterval(-2),
                    hostVersion: nil
                ),
                kimiPIDs: kimiPIDs,
                now: now
            )
        )
    }

    func testParsesLsofOutputForMultiplePIDsAndPathsWithSpaces() {
        let output = """
        p3407
        fcwd
        n/Users/diego/My Projects/kimi app
        p70539
        fcwd
        n/tmp/other workspace
        p88001
        f1
        n/dev/null
        """

        let parsed = KimiCodeWebActivityDetector.parseWorkingDirectories(fromLsofOutput: output)
        XCTAssertEqual(
            parsed[3407]?.path,
            "/Users/diego/My Projects/kimi app"
        )
        XCTAssertEqual(parsed[70539]?.path, "/tmp/other workspace")
        XCTAssertNil(parsed[88001])
    }

    func testMatchesSessionOwnershipOnlyToLiveInstanceWorkspace() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let liveWorkspace = home.appendingPathComponent("pressbot", isDirectory: true)
        let otherWorkspace = home.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: liveWorkspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherWorkspace, withIntermediateDirectories: true)

        try writeInstance(
            pid: 3407,
            startedAt: now.addingTimeInterval(-60),
            heartbeatAt: now.addingTimeInterval(-2),
            home: home
        )
        try writeSession(id: "session_owned", cwd: liveWorkspace.path, home: home)
        try writeSession(id: "session_other", cwd: otherWorkspace.path, home: home)
        try writeRawSession("{not-json", home: home, folder: "broken")
        try writeRawSession(
            #"{"cwd":"/tmp","id":"../escape"}"#,
            home: home,
            folder: "unsafe"
        )
        try writeEvents(
            """
            \(workChanged(active: true, at: now.addingTimeInterval(-5), seq: 1))

            """,
            sessionID: "session_owned",
            home: home
        )
        try writeEvents(
            """
            \(workChanged(active: true, at: now.addingTimeInterval(-5), seq: 1))

            """,
            sessionID: "session_other",
            home: home
        )

        XCTAssertTrue(
            KimiCodeWebActivityDetector.isAgentRunning(
                in: "  3407 kimi\n",
                homeDirectory: home,
                now: now,
                workingDirectoriesByPID: [3407: liveWorkspace]
            )
        )

        XCTAssertNil(
            KimiCodeWebActivityDetector.parseSessionState(from: Data("{not-json".utf8))
        )
        XCTAssertFalse(KimiCodeWebActivityDetector.isSafeSessionID("../escape"))
        XCTAssertFalse(KimiCodeWebActivityDetector.isSafeSessionID("session/../id"))
        XCTAssertFalse(KimiCodeWebActivityDetector.isSafeSessionID(""))
        XCTAssertTrue(KimiCodeWebActivityDetector.isSafeSessionID("session_9524bab8-fb23-40ad-a692-da41791335d1"))
    }

    func testDetectsActiveTurnWhenSessionCWDDiffersFromServerLaunchDirectory() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let launchDirectory = home.appendingPathComponent("launch-workspace", isDirectory: true)
        let sessionWorkspace = home.appendingPathComponent("other-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: launchDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionWorkspace, withIntermediateDirectories: true)

        try writeInstance(
            pid: 3407,
            startedAt: now.addingTimeInterval(-60),
            heartbeatAt: now.addingTimeInterval(-2),
            home: home
        )
        try writeSession(id: "session_cross_workspace", cwd: sessionWorkspace.path, home: home)
        try writeEvents(
            """
            \(workChanged(active: true, at: now.addingTimeInterval(-5), seq: 1))

            """,
            sessionID: "session_cross_workspace",
            home: home
        )

        XCTAssertTrue(
            KimiCodeWebActivityDetector.isAgentRunning(
                in: "  3407 kimi\n",
                homeDirectory: home,
                now: now,
                workingDirectoriesByPID: [3407: launchDirectory]
            )
        )
    }

    func testOlderLiveServerDoesNotInheritCrashedNewerServersActiveTurn() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let olderLaunch = home.appendingPathComponent("older-launch", isDirectory: true)
        let sessionWorkspace = home.appendingPathComponent("other-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: olderLaunch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionWorkspace, withIntermediateDirectories: true)

        try writeInstance(
            pid: 3407,
            startedAt: now.addingTimeInterval(-3600),
            heartbeatAt: now.addingTimeInterval(-2),
            home: home,
            name: "older-live"
        )
        try writeInstance(
            pid: 88001,
            startedAt: now.addingTimeInterval(-180),
            heartbeatAt: now.addingTimeInterval(-90),
            home: home,
            name: "newer-crashed"
        )
        try writeSession(id: "session_crashed_turn", cwd: sessionWorkspace.path, home: home)
        try writeEvents(
            """
            \(workChanged(active: true, at: now.addingTimeInterval(-100), seq: 1))

            """,
            sessionID: "session_crashed_turn",
            home: home
        )

        XCTAssertFalse(
            KimiCodeWebActivityDetector.isAgentRunning(
                in: "  3407 kimi\n",
                homeDirectory: home,
                now: now,
                workingDirectoriesByPID: [3407: olderLaunch]
            )
        )
    }

    func testActiveEventAfterCrashedNewerServerWindowIsAttributedToOlderLiveServer() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let olderLaunch = home.appendingPathComponent("older-launch", isDirectory: true)
        let sessionWorkspace = home.appendingPathComponent("other-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: olderLaunch, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessionWorkspace, withIntermediateDirectories: true)

        try writeInstance(
            pid: 3407,
            startedAt: now.addingTimeInterval(-3600),
            heartbeatAt: now.addingTimeInterval(-2),
            home: home,
            name: "older-live"
        )
        try writeInstance(
            pid: 88001,
            startedAt: now.addingTimeInterval(-180),
            heartbeatAt: now.addingTimeInterval(-90),
            home: home,
            name: "newer-crashed"
        )
        try writeSession(id: "session_after_crash_window", cwd: sessionWorkspace.path, home: home)
        try writeEvents(
            """
            \(workChanged(active: true, at: now.addingTimeInterval(-10), seq: 1))

            """,
            sessionID: "session_after_crash_window",
            home: home
        )

        XCTAssertTrue(
            KimiCodeWebActivityDetector.isAgentRunning(
                in: "  3407 kimi\n",
                homeDirectory: home,
                now: now,
                workingDirectoriesByPID: [3407: olderLaunch]
            )
        )
    }

    func testReportsActiveForWorkChangedMainTurnActive() {
        let events = """
        \(workChanged(active: false, at: now.addingTimeInterval(-30), seq: 1, reason: "completed"))
        \(workChanged(active: true, at: now.addingTimeInterval(-2), seq: 2))

        """

        XCTAssertEqual(
            KimiCodeWebActivityDetector.classifyLatestDecisiveEvent(in: events)?.isActive,
            true
        )
    }

    func testReportsIdleWhenLaterWorkChangedClearsTheTurn() {
        let completed = """
        \(workChanged(active: true, at: now.addingTimeInterval(-20), seq: 1))
        \(event(type: "turn.ended", at: now.addingTimeInterval(-3), seq: 2))
        \(workChanged(active: false, at: now.addingTimeInterval(-2), seq: 3, reason: "completed"))

        """
        let failed = """
        \(workChanged(active: true, at: now.addingTimeInterval(-20), seq: 1))
        \(workChanged(active: false, at: now.addingTimeInterval(-2), seq: 2, reason: "failed"))

        """

        XCTAssertEqual(
            KimiCodeWebActivityDetector.classifyLatestDecisiveEvent(in: completed)?.isActive,
            false
        )
        XCTAssertEqual(
            KimiCodeWebActivityDetector.classifyLatestDecisiveEvent(in: failed)?.isActive,
            false
        )
    }

    func testReportsActiveForInTurnLifecycleWhenWorkChangedHasFallenOutOfTail() {
        let types = [
            "turn.started",
            "turn.step.started",
            "turn.step.completed",
            "tool.call.started",
            "tool.result"
        ]

        for type in types {
            let events = """
            \(event(type: "session.context", at: now.addingTimeInterval(-8), seq: 1))
            \(event(type: type, at: now.addingTimeInterval(-2), seq: 2))

            """
            XCTAssertEqual(
                KimiCodeWebActivityDetector.classifyLatestDecisiveEvent(in: events)?.isActive,
                true,
                "Expected \(type) to keep the turn active"
            )
        }
    }

    func testReportsIdleForTerminalLifecycleEvents() {
        for type in ["turn.ended", "prompt.completed", "turn.step.interrupted"] {
            let events = """
            \(workChanged(active: true, at: now.addingTimeInterval(-20), seq: 1))
            \(event(type: type, at: now.addingTimeInterval(-2), seq: 2))

            """
            XCTAssertEqual(
                KimiCodeWebActivityDetector.classifyLatestDecisiveEvent(in: events)?.isActive,
                false,
                "Expected \(type) to mark the turn idle"
            )
        }
    }

    func testSkipsPartialNewestLineAndKeepsPrecedingActiveState() {
        let events = """
        \(workChanged(active: true, at: now.addingTimeInterval(-4), seq: 1))
        {"kind":"event","seq":2,"envelope":{"type":"event.session.work_changed","payload":{"main_turn_active":
        """

        XCTAssertEqual(
            KimiCodeWebActivityDetector.classifyLatestDecisiveEvent(in: events)?.isActive,
            true
        )
    }

    func testFailsClosedForUnknownOversizedMissingAndUnreadableEvents() throws {
        let unknown = """
        {"kind":"event","seq":1,"envelope":{"type":"session.metadata","timestamp":"\(iso(now))","payload":{}}}
        {"kind":"event","seq":2,"envelope":{"type":"context.updated","timestamp":"\(iso(now))","payload":{}}}

        """
        XCTAssertNil(KimiCodeWebActivityDetector.classifyLatestDecisiveEvent(in: unknown))

        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let eventsDirectory = home
            .appendingPathComponent("events", isDirectory: true)
        try FileManager.default.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)

        let oversized = eventsDirectory.appendingPathComponent("oversized.jsonl")
        var unknownBlock = ""
        while unknownBlock.utf8.count < 2048 {
            unknownBlock += """
            {"kind":"event","seq":1,"envelope":{"type":"session.metadata","timestamp":"\(iso(now))","payload":{}}}\n
            """
        }
        try unknownBlock.write(to: oversized, atomically: true, encoding: .utf8)
        XCTAssertNil(
            KimiCodeWebActivityDetector.latestTurnActivity(
                inEventFileAt: oversized,
                searchLimit: 512
            )
        )

        let missing = eventsDirectory.appendingPathComponent("missing.jsonl")
        XCTAssertNil(KimiCodeWebActivityDetector.latestTurnActivity(inEventFileAt: missing))

        let unreadable = eventsDirectory.appendingPathComponent("unreadable.jsonl")
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        XCTAssertNil(KimiCodeWebActivityDetector.latestTurnActivity(inEventFileAt: unreadable))
    }

    func testRejectsEventActivityOlderThanMatchingInstanceStart() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let workspace = home.appendingPathComponent("pressbot", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let startedAt = now.addingTimeInterval(-30)
        try writeInstance(pid: 3407, startedAt: startedAt, heartbeatAt: now.addingTimeInterval(-1), home: home)
        try writeSession(id: "session_stale", cwd: workspace.path, home: home)
        try writeEvents(
            """
            \(workChanged(active: true, at: startedAt.addingTimeInterval(-5), seq: 1))

            """,
            sessionID: "session_stale",
            home: home
        )

        XCTAssertFalse(
            KimiCodeWebActivityDetector.isAgentRunning(
                in: "  3407 kimi\n",
                homeDirectory: home,
                now: now,
                workingDirectoriesByPID: [3407: workspace]
            )
        )
    }

    func testAggregatesMultipleInstancesAndReturnsTrueWhenOneSessionIsActive() throws {
        let home = try makeTemporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let activeWorkspace = home.appendingPathComponent("pressbot", isDirectory: true)
        let idleWorkspace = home.appendingPathComponent("wiki", isDirectory: true)
        try FileManager.default.createDirectory(at: activeWorkspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: idleWorkspace, withIntermediateDirectories: true)

        try writeInstance(
            pid: 3407,
            startedAt: now.addingTimeInterval(-90),
            heartbeatAt: now.addingTimeInterval(-2),
            home: home,
            name: "active-server"
        )
        try writeInstance(
            pid: 70539,
            startedAt: now.addingTimeInterval(-3600),
            heartbeatAt: now.addingTimeInterval(-4),
            home: home,
            name: "idle-server"
        )
        try writeSession(id: "session_active", cwd: activeWorkspace.path, home: home, folder: "wd_pressbot")
        try writeSession(id: "session_idle", cwd: idleWorkspace.path, home: home, folder: "wd_wiki")
        try writeEvents(
            """
            \(workChanged(active: true, at: now.addingTimeInterval(-8), seq: 1))
            \(event(type: "turn.step.started", at: now.addingTimeInterval(-3), seq: 2))

            """,
            sessionID: "session_active",
            home: home
        )
        try writeEvents(
            """
            \(workChanged(active: false, at: now.addingTimeInterval(-6), seq: 9, reason: "completed"))

            """,
            sessionID: "session_idle",
            home: home
        )

        XCTAssertTrue(
            KimiCodeWebActivityDetector.isAgentRunning(
                in: """
                  3407 /opt/homebrew/bin/kimi
                 70539 kimi
                """,
                homeDirectory: home,
                now: now,
                workingDirectoriesByPID: [
                    3407: activeWorkspace,
                    70539: idleWorkspace
                ]
            )
        )
    }

    func testIgnoresUnrelatedMetadataWhileScanningBackward() {
        let events = """
        \(workChanged(active: true, at: now.addingTimeInterval(-10), seq: 1))
        \(event(type: "session.title_changed", at: now.addingTimeInterval(-2), seq: 2))
        \(event(type: "context.updated", at: now.addingTimeInterval(-1), seq: 3))

        """

        XCTAssertEqual(
            KimiCodeWebActivityDetector.classifyLatestDecisiveEvent(in: events)?.isActive,
            true
        )
    }

    private func makeTemporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("chorreador-kimi-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func writeInstance(
        pid: Int,
        startedAt: Date,
        heartbeatAt: Date,
        home: URL,
        name: String = "instance"
    ) throws {
        try writeRawInstance(
            String(data: instanceJSON(pid: pid, startedAt: startedAt, heartbeatAt: heartbeatAt), encoding: .utf8) ?? "",
            home: home,
            name: name
        )
    }

    private func writeRawInstance(_ contents: String, home: URL, name: String) throws {
        let directory = home
            .appendingPathComponent(".kimi-code", isDirectory: true)
            .appendingPathComponent("server", isDirectory: true)
            .appendingPathComponent("instances", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try contents.write(
            to: directory.appendingPathComponent("\(name).json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeSession(id: String, cwd: String, home: URL, folder: String = "wd_workspace") throws {
        let directory = home
            .appendingPathComponent(".kimi-code", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent("session_\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = """
        {"id":"\(id)","cwd":"\(cwd)"}
        """
        try json.write(
            to: directory.appendingPathComponent("state.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeRawSession(_ contents: String, home: URL, folder: String) throws {
        let directory = home
            .appendingPathComponent(".kimi-code", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent("session_raw", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try contents.write(
            to: directory.appendingPathComponent("state.json"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeEvents(_ contents: String, sessionID: String, home: URL) throws {
        let directory = home
            .appendingPathComponent(".kimi-code", isDirectory: true)
            .appendingPathComponent("server", isDirectory: true)
            .appendingPathComponent("events", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try contents.write(
            to: directory.appendingPathComponent("\(sessionID).jsonl"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func instanceJSON(
        pid: Int,
        startedAt: Date,
        heartbeatAt: Date,
        version: String = "0.36.1"
    ) -> Data {
        Data(
            """
            {"pid":\(pid),"started_at":\(milliseconds(startedAt)),"heartbeat_at":\(milliseconds(heartbeatAt)),"host":"127.0.0.1","port":58627,"host_version":"\(version)"}
            """.utf8
        )
    }

    private func workChanged(active: Bool, at date: Date, seq: Int, reason: String? = nil) -> String {
        var payload = "\"type\":\"event.session.work_changed\",\"busy\":\(active),\"main_turn_active\":\(active)"
        if let reason {
            payload += ",\"last_turn_reason\":\"\(reason)\""
        }
        return event(type: "event.session.work_changed", at: date, seq: seq, payload: "{\(payload)}")
    }

    private func event(type: String, at date: Date, seq: Int, payload: String = "{}") -> String {
        """
        {"kind":"event","seq":\(seq),"envelope":{"type":"\(type)","seq":\(seq),"timestamp":"\(iso(date))","payload":\(payload)}}
        """
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func milliseconds(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded())
    }
}
