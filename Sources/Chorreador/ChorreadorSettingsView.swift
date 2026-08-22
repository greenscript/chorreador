import SwiftUI

struct ChorreadorSettingsView: View {
    @ObservedObject var powerManager: PowerManager

    var body: some View {
        TabView {
            GeneralSettingsView(powerManager: powerManager)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AgentSettingsView(powerManager: powerManager)
                .tabItem {
                    Label("Agents", systemImage: "terminal")
                }

            BatterySettingsView(powerManager: powerManager)
                .tabItem {
                    Label("Battery", systemImage: "battery.75")
                }

            JournalSettingsView(journal: powerManager.journal)
                .tabItem {
                    Label("Journal", systemImage: "book.closed")
                }
        }
        .frame(width: 520, height: 420)
        .onAppear {
            powerManager.refreshLaunchAtLoginStatus()
        }
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var powerManager: PowerManager

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Chorreador at login", isOn: launchAtLoginBinding)

                if powerManager.launchAtLoginNeedsApproval {
                    Label(
                        "Approve Chorreador in System Settings → General → Login Items.",
                        systemImage: "exclamationmark.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section("Sleep behavior") {
                Toggle("Let the display rest", isOn: $powerManager.letDisplaySleep)

                Text("Recommended. Chorreador keeps agent sessions running without forcing the screen to stay lit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Notify me when the pour changes", isOn: notificationsBinding)

                Text("Notifications appear only when an agent pour starts, finishes, or pauses for battery care.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { powerManager.launchAtLoginEnabled },
            set: powerManager.setLaunchAtLoginEnabled
        )
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { powerManager.notificationsEnabled },
            set: powerManager.setNotificationsEnabled
        )
    }
}

private struct AgentSettingsView: View {
    @ObservedObject var powerManager: PowerManager
    @State private var customProcessName = ""
    @FocusState private var customProcessFieldFocused: Bool

    var body: some View {
        Form {
            Section("Automatic detection") {
                Toggle("Auto-pour when an agent is running", isOn: $powerManager.automaticDetectionEnabled)

                Text("Chorreador checks local process names every 10 seconds. Nothing leaves your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Built-in agents") {
                ForEach(CodingAgent.allCases, id: \.self) { agent in
                    ProcessStatusRow(
                        name: agent.displayName,
                        isRunning: powerManager.detectedAgents.contains(agent)
                    )
                }
            }

            Section("Custom processes") {
                HStack {
                    TextField("aider, or a fragment like scripts/my-job.sh", text: $customProcessName)
                        .focused($customProcessFieldFocused)
                        .onSubmit(addCustomProcess)

                    Button("Add", action: addCustomProcess)
                        .disabled(customProcessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Text("A plain name matches an executable. Include a space or / to match anywhere in the command line — useful for tools that run inside python or node, such as “hermes --provider”. Keep fragments specific to the job, so an always-on daemon can’t hold the pour forever.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !powerManager.customProcessNames.isEmpty {
                    ForEach(powerManager.customProcessNames, id: \.self) { processName in
                        HStack {
                            ProcessStatusRow(
                                name: processName,
                                isRunning: powerManager.detectedCustomProcesses.contains(processName),
                                usesMonospacedName: true
                            )

                            Spacer()

                            Button(role: .destructive) {
                                powerManager.removeCustomProcess(processName)
                            } label: {
                                Label("Remove \(processName)", systemImage: "minus.circle")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(processName)")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func addCustomProcess() {
        powerManager.addCustomProcess(customProcessName)
        customProcessName = ""
        customProcessFieldFocused = true
    }
}

private struct ProcessStatusRow: View {
    let name: String
    let isRunning: Bool
    var usesMonospacedName = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRunning ? ChorreadorPalette.rainforest : Color.secondary.opacity(0.28))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(name)
                .font(usesMonospacedName ? .system(.body, design: .monospaced) : .body)

            Spacer()

            if isRunning {
                Text("Running")
                    .font(.caption)
                    .foregroundStyle(ChorreadorPalette.rainforest)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(isRunning ? "running" : "not running")")
    }
}

private struct JournalSettingsView: View {
    @ObservedObject var journal: PourJournal

    var body: some View {
        Form {
            Section("This week") {
                LabeledContent("Protected time") {
                    Text(brewDurationText(weeklyProtected))
                        .monospacedDigit()
                }

                Text("Time your Mac was kept awake for agents over the last 7 days, minus any sleep interruptions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Recent pours") {
                if recentRecords.isEmpty {
                    Text("No pours recorded yet. The journal starts writing the next time a pour begins.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recentRecords) { record in
                        PourRecordRow(record: record)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var weeklyProtected: TimeInterval {
        let now = Date()
        return journal.protectedDuration(from: now.addingTimeInterval(-7 * 86_400), to: now)
    }

    private var recentRecords: [PourRecord] {
        journal.records.suffix(12).reversed()
    }
}

private struct PourRecordRow: View {
    let record: PourRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(record.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.callout)

                Spacer()

                Text(brewDurationText(record.duration(asOf: Date())))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Text(record.sources.joined(separator: " + "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(spacing: 5) {
                Image(systemName: outcomeIcon)
                    .font(.caption2)
                Text(outcomeText)
                    .font(.caption)
            }
            .foregroundStyle(record.interruptions.isEmpty ? Color.secondary : .orange)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var outcomeIcon: String {
        if record.isOpen { return "drop.fill" }
        if !record.interruptions.isEmpty { return "moon.zzz.fill" }
        switch record.endReason {
        case .batteryPause: return "battery.25"
        case .appQuit: return "exclamationmark.circle"
        case .finished, nil: return "checkmark.circle"
        }
    }

    private var outcomeText: String {
        if record.isOpen { return "Flowing now" }
        if !record.interruptions.isEmpty {
            let lost = brewDurationText(record.totalSleepLost)
            return "Slept \(record.interruptions.count)× mid-pour · \(lost) lost"
        }
        switch record.endReason {
        case .batteryPause: return "Paused for battery care"
        case .appQuit: return "Cut short — Chorreador quit mid-pour"
        case .finished, nil: return "Clean finish"
        }
    }
}

private struct BatterySettingsView: View {
    @ObservedObject var powerManager: PowerManager

    var body: some View {
        Form {
            Section("Current power") {
                LabeledContent("Battery") {
                    Label(batteryDescription, systemImage: batteryIcon)
                }
            }

            Section("Battery care") {
                Toggle(
                    "Pause pours at \(PowerManager.lowBatteryThreshold)% on battery",
                    isOn: $powerManager.lowBatteryGuardEnabled
                )

                Text("Connecting power resumes protection automatically. macOS critical-battery safeguards always take precedence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Label("Display sleep remains available when “Let the display rest” is enabled.", systemImage: "display")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var batteryDescription: String {
        let percentage = powerManager.battery.percentage.map { "\($0)%" } ?? "Unknown"
        if powerManager.battery.isCharging { return "\(percentage), charging" }
        return powerManager.battery.isOnBattery ? "\(percentage), on battery" : "\(percentage), connected"
    }

    private var batteryIcon: String {
        if powerManager.battery.isCharging { return "battery.100.bolt" }
        guard let percentage = powerManager.battery.percentage else { return "battery.100" }
        if percentage <= 25 { return "battery.25" }
        if percentage <= 50 { return "battery.50" }
        if percentage <= 75 { return "battery.75" }
        return "battery.100"
    }
}
