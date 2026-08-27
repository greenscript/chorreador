# Kimi Code Web activity support — implementation handoff

Status: ready for Cursor implementation and subsequent Codex review
Base: `main` at `f2f434d` (`v1.4.0`)
Delivery shape: one bounded wave, left uncommitted for review

## Objective

Recognize an actively running Kimi Code Web turn as a built-in coding-agent source so Chorreador prevents idle system sleep for the full turn. Keep an open but idle `kimi web` server and browser tab from holding the Mac awake.

This feature is specifically for Kimi Code Web (`kimi web` or the in-CLI `/web` flow). Do not broaden it into generic detection of every persistent `kimi` TUI/CLI process in this change.

## Non-negotiable behavior

- A Kimi turn becomes visible as `Kimi Code` in Chorreador's detected-agent names and participates in the existing automatic pour, journal, notifications, battery guard, and display-sleep preference without adding a parallel power-management path.
- Detection follows turn activity, not process lifetime, tab lifetime, browser lifetime, network-socket lifetime, or CPU usage.
- An idle Kimi Web server must not keep the Mac awake. The foreground `kimi` process remains alive after a turn completes, so executable-name matching alone is explicitly incorrect.
- A long reasoning step or tool call remains protected even when the local event file is temporarily quiet.
- Completion, failure, interruption, or server shutdown returns Kimi to idle by the next normal 10-second agent scan.
- Missing files, malformed JSON, stale instance registrations, unreadable process metadata, unknown event types, or unsupported future formats fail closed: report Kimi idle and never crash or block the scan.
- Detection remains local-only. Do not call Kimi's REST/WebSocket API, read `~/.kimi-code/server.token`, inspect browser tabs/DOM, use AppleScript, or add browser-specific permissions.
- Do not log or surface prompt text, model output, tool arguments/results, tokens, credentials, or full event payloads. Only lifecycle metadata is needed.
- Preserve all current behavior and tests for Claude, Codex, Cursor, OpenCode, T3 Code, custom processes, battery care, and manual/timed pours.

## Evidence behind the design

The running local installation supplied the following evidence on August 26, 2026:

- Kimi Code `0.36.1` was running a Web session at `127.0.0.1:58627`; another idle Web instance (`0.30.0`) coexisted on port `58628`.
- Both instances had long-lived processes whose command was only `kimi`; process presence therefore cannot distinguish active from idle.
- Each live instance registered a small JSON document under `~/.kimi-code/server/instances/` with `pid`, `started_at`, `heartbeat_at`, `host`, `port`, and `host_version`.
- Session metadata lived under `~/.kimi-code/sessions/*/session_*/state.json` and included `id` and `cwd`.
- Web replay events lived at `~/.kimi-code/server/events/<session-id>.jsonl` with the top-level shape `{ "kind", "seq", "envelope" }`.
- At turn start, the stream emitted `event.session.work_changed` whose payload had `busy: true` and `main_turn_active: true`. On completed and failed turns it emitted a later work-change event with both values false. The stream also showed the documented lifecycle `turn.started` → step/tool events → `turn.ended` → `prompt.completed`.
- The active browser UI showed `Working…` and an enabled `Interrupt` control, but browser inspection is intentionally not an implementation dependency.

Kimi's official documentation confirms that `kimi web` is a long-lived foreground local server, that multiple registered instances can coexist, and that its event lifecycle includes `turn.started`, tool events, and `turn.ended`:

- <https://www.kimi.com/code/docs/en/kimi-code-cli/guides/server.html>
- <https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-command>

The documented API is experimental and requires a bearer token with powerful local-session access. Chorreador must not use that API for this feature.

## Existing code map

- `Sources/Chorreador/AgentProcessDetector.swift`
  - owns `CodingAgent`, display names, the shared `ps` snapshot, and detector aggregation;
  - desktop-aware sources are inserted after generic CLI matching.
- `Sources/Chorreador/CodexDesktopActivityDetector.swift`
  - useful precedent for extracting PIDs and failing closed around a local activity store.
- `Sources/Chorreador/ClaudeDesktopActivityDetector.swift`
  - useful precedent for bounded JSONL-tail parsing and avoiding full-file reads.
- `Sources/Chorreador/CursorDesktopActivityDetector.swift`
  - useful precedent for separating an always-open host process from a persisted active-turn signal.
- `Sources/Chorreador/PowerManager.swift`
  - already turns any nonempty detected-agent set into the existing wake assertion, journal source, and notifications. No Kimi-specific branch belongs here.
- `Tests/ChorreadorTests/AgentProcessDetectorTests.swift`
  - regression coverage for generic process matching and branded persistent hosts.

## Worktree boundary

The repository was already dirty before this spec was created:

- `README.md`
- `Sources/Chorreador/CodexDesktopActivityDetector.swift`
- `Tests/ChorreadorTests/CodexDesktopActivityDetectorTests.swift`

Those edits belong to the user. Preserve them exactly. The Kimi work must coexist with the README edit, but must not rewrite or revert the Codex detector/test changes. Leave the implementation uncommitted.

## Required architecture

### 1. Register Kimi as a built-in agent

Add a `CodingAgent` case for Kimi with the displayed source name `Kimi Code`.

Do not teach `AgentProcessDetector.detect(in:)` to treat every executable named `kimi` as active. A plain Kimi process may be a waiting TUI or an idle Web server. Instead, call a dedicated `KimiCodeWebActivityDetector.isAgentRunning(...)` from `runningDetection(...)`, alongside the existing Codex/Claude/Cursor desktop-aware checks, and insert the Kimi case only when that detector returns true.

### 2. Add `KimiCodeWebActivityDetector.swift`

Keep orchestration thin and isolate parsing into pure/testable helpers. Exact private type names are flexible, but the detector must enforce all of the following gates:

1. **Live Web instance gate**
   - Read `~/.kimi-code/server/instances/*.json`.
   - Decode only the fields needed for detection (`pid`, `started_at`, `heartbeat_at`; `host_version` may be retained for diagnostics/tests but must not be logged).
   - Accept an instance only when:
     - its PID is present in the current shared `ps` snapshot and the executable basename is exactly `kimi` (support an absolute path or the observed process title `kimi`);
     - its heartbeat is fresh. Use a tolerant, explicit ceiling of 60 seconds so the existing 10-second Chorreador scan and brief scheduler delays do not flap;
     - its process working directory can be resolved.
   - Resolve the working directory for the small set of accepted PIDs with one `/usr/sbin/lsof -a -p <comma-separated-pids> -d cwd -Fn` invocation. Parse `p<PID>`, `fcwd`, and `n<path>` records. Do not invoke `lsof` for arbitrary processes.
   - If the instance directory is missing, the heartbeat is stale, the PID does not match, or `lsof` fails, ignore that instance.

2. **Session ownership gate**
   - Enumerate session state files beneath `~/.kimi-code/sessions/` and decode only `id` and `cwd` from `state.json`.
   - Standardize paths consistently (and resolve symlinks when practical) before comparing them.
   - A session is a candidate only when its `cwd` matches the working directory of a live Web instance and its ID is a safe expected session ID (at minimum, a nonempty filename-safe component). Construct the event URL with `appendingPathComponent`; never concatenate an untrusted absolute path.
   - Require the candidate's latest decisive event timestamp to be no earlier than the matching live instance's `started_at`. This prevents a restarted server from inheriting an unfinished event state written by an older dead process.

3. **Turn-state gate**
   - Read from the end of `~/.kimi-code/server/events/<session-id>.jsonl`, not from the beginning on every 10-second scan.
   - Implement a reverse/chunked reader that skips an incomplete leading fragment and malformed lines, parses envelopes from newest to oldest, and stops at the first decisive lifecycle record. Avoid loading the complete replay file or deserializing large prompt/tool payloads.
   - Prefer the authoritative `event.session.work_changed` record:
     - `payload.main_turn_active == true` means active;
     - a later record with `main_turn_active == false` means idle regardless of its completion reason.
   - The bounded recent-event classifier must also preserve activity if the start work-change record has fallen outside the tail during a large/long turn. Treat these most-recent lifecycle types as active evidence while a live matching instance exists: `turn.started`, `turn.step.started`, `turn.step.completed`, `tool.call.started`, and `tool.result`.
   - Treat `turn.ended`, `prompt.completed`, and `turn.step.interrupted` as idle evidence when they are the newest decisive record. Ignore unrelated metadata/context records and continue scanning backward.
   - A partially written newest JSONL record must not flip an active turn to idle: skip that invalid fragment and evaluate the previous complete decisive record.
   - Bound worst-case reads. Start with small reverse chunks and stop as soon as a decisive record is found; cap the total tail search at 8 MiB. If no decisive record is found within the cap, fail closed.

4. **Result aggregation**
   - Return true when any candidate session owned by any live Kimi Web instance is active.
   - Multiple simultaneous Kimi Web instances and multiple sessions in one workspace must be supported.
   - Do all file/process work inside the existing detached utility scan; do not add timers or observable state to the detector.

### 3. Documentation and visible naming

Update `README.md` to:

- list **Kimi Code Web** under supported agents;
- explain in the behavior paragraph that Kimi Web is detected from local turn lifecycle metadata, not merely from the persistent local server or browser tab;
- include Kimi turn lifecycle metadata in the local/private desktop-status language without implying that prompts or tool contents are read.

No new settings, icons, menu controls, preferences, migrations, or journal schema are needed. Existing generic rendering should display `Kimi Code` automatically.

## Failure and compatibility behavior

- The detector must return false on any subprocess, file-system, decoding, or format error and allow the other detectors to finish normally.
- Never delete, truncate, lock, rewrite, or migrate Kimi files.
- Open event files read-only and close handles promptly.
- Do not assume port `58627`; multiple instances increment ports.
- Do not assume one server, one workspace, one session, Chrome, a focused/visible tab, or an established remote socket.
- Do not hold a lease after an explicit Kimi terminal event. The ordinary next 10-second scan is the intended release latency.
- Do not add a generic `kimi` custom-process default or silently persist any new preference.
- Internal Kimi file formats may change. Unknown schema must degrade to no detection, not optimistic detection.

## Required automated coverage

Add `Tests/ChorreadorTests/KimiCodeWebActivityDetectorTests.swift` and narrowly extend `AgentProcessDetectorTests.swift`.

At minimum cover:

1. Parses multiple live instance records and accepts an exact `kimi` PID from the process list.
2. Rejects a stale heartbeat, missing PID, PID reused by a non-Kimi command, malformed instance JSON, and failed/missing cwd lookup.
3. Parses `lsof -Fn` output for multiple PIDs and paths containing spaces.
4. Matches session `id`/`cwd` only to a live instance workspace and ignores malformed/unrelated state files.
5. Reports active for `event.session.work_changed` with `main_turn_active: true`.
6. Reports idle when a later work-change record sets `main_turn_active: false`, including completed and failed examples.
7. Reports active when the newest decisive event is `turn.started`, a turn-step event, `tool.call.started`, or `tool.result`; this models a long turn whose initial work-change event is outside the bounded tail.
8. Reports idle for newest `turn.ended`, `prompt.completed`, or `turn.step.interrupted`.
9. Skips a malformed/partially written newest line and preserves the preceding decisive active state.
10. Fails closed for unknown-only, oversized-without-decisive-event, missing, and unreadable event inputs.
11. Rejects event activity older than the matching server instance start time.
12. Aggregates multiple instances/sessions and returns true if exactly one matching session is active.
13. Confirms a bare idle `kimi` process is **not** detected by generic process matching and that an active Kimi Web detector result maps to the `.kimiCode` built-in agent.
14. Keeps all existing detector regression tests passing.

Use temporary directories and injected `now`/cwd lookup or pure parser inputs so unit tests never depend on the developer's real `~/.kimi-code`, live PIDs, browser, bearer token, or network.

## Verification commands

Run from the repository root:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache" \
swift test --disable-sandbox

zsh scripts/build-app.sh debug
```

Baseline before implementation: 53 tests passed with zero failures on August 26, 2026. SwiftPM printed read-only user-cache warnings, but the build and suite succeeded.

## Manual regression matrix for Codex review

The user should initiate/stop Kimi prompts; do not send prompts or interrupt their live work without explicit approval.

| Scenario | Expected result within one 10-second scan |
|---|---|
| `kimi web` running, tab open, no active turn | `Kimi Code` absent; no Kimi-caused pour |
| Active reasoning/streaming | `Kimi Code` present; automatic pour active |
| Long local tool call with no fresh event writes | Remains present until the turn terminates |
| Turn completes normally | `Kimi Code` disappears |
| Turn fails | `Kimi Code` disappears |
| User interrupts turn | `Kimi Code` disappears |
| Server exits mid-turn | `Kimi Code` disappears because the live-instance gate fails |
| Two servers: one idle, one active | One `Kimi Code` source; pour remains active |
| Corrupt/missing Kimi metadata | No crash, no Kimi detection, other agents still detected |
| Auto-pour disabled or low-battery guard engaged | Existing policy behavior remains authoritative |

During review, also confirm the menu source, notification copy, and journal source use `Kimi Code` through the existing generic flow. When no other source/manual timer is active, inspect `pmset -g assertions` to confirm the Chorreador idle-system-sleep assertion appears only during the active Kimi turn.

## Explicit exclusions

- Kimi TUI/print/ACP detection independent of Web mode.
- Kimi API/WebSocket integration or token handling.
- Browser extension, browser DOM/title polling, Chrome/Safari-specific behavior, or Accessibility/Automation permissions.
- Remote Kimi servers, nonlocal account activity, Windows/Linux support, analytics, new settings, and release/version bump work.
- Commit, tag, push, packaging, notarization, deployment, or GitHub release creation.

## Cursor delivery request

Implement this specification in one wave using Cursor's economical automatic mode. Preserve the pre-existing dirty files and unrelated changes. Run the focused/full tests and debug build, then report:

- exact files changed;
- concise architecture summary and any intentional deviations from this spec;
- test/build commands and results;
- remaining manual Kimi scenarios that require the user's live app;
- `git diff --stat` and `git status --short`.

Leave all changes uncommitted for Codex review.
