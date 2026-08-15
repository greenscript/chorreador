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
                    TextField("Executable name, such as aider", text: $customProcessName)
                        .focused($customProcessFieldFocused)
                        .onSubmit(addCustomProcess)

                    Button("Add", action: addCustomProcess)
                        .disabled(customProcessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if powerManager.customProcessNames.isEmpty {
                    Text("Add an executable name to include another local agent or long-running tool.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
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
