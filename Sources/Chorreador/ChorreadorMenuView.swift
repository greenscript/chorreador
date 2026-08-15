import AppKit
import SwiftUI

struct ChorreadorMenuView: View {
    @ObservedObject var powerManager: PowerManager

    var body: some View {
        VStack(spacing: 0) {
            BrewStatusHeader(
                policy: powerManager.policy,
                automaticPour: powerManager.isAutomaticallyProtecting,
                detectedNames: powerManager.detectedProcessDisplayNames,
                pourStartedAt: powerManager.pourStartedAt,
                displayMayRest: powerManager.letDisplaySleep,
                automaticDetectionEnabled: powerManager.automaticDetectionEnabled
            )

            AutoPourControl(
                isEnabled: $powerManager.automaticDetectionEnabled,
                detectedNames: powerManager.detectedProcessDisplayNames
            )

            Divider()
                .padding(.horizontal, 16)

            PourActions(
                manualPourEnabled: $powerManager.protectionEnabled,
                timerEndDate: powerManager.brewTimerEndDate,
                startTimer: powerManager.startBrewTimer,
                cancelTimer: powerManager.cancelBrewTimer
            )

            Divider()
                .padding(.horizontal, 16)

            MenuFooter()
        }
        .frame(width: 340)
        .background(.regularMaterial)
    }
}

private struct BrewStatusHeader: View {
    let policy: WakePolicy
    let automaticPour: Bool
    let detectedNames: [String]
    let pourStartedAt: Date?
    let displayMayRest: Bool
    let automaticDetectionEnabled: Bool

    private var isFlowing: Bool {
        policy == .protectingSystem || policy == .protectingSystemAndDisplay
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(ChorreadorPalette.parchment)
                        .accessibilityHidden(true)

                    Text("CHORREADOR")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .tracking(1.5)

                    Spacer()

                    Text(statusLabel)
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .tracking(0.7)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.14), in: Capsule())
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .lineLimit(1)
                    Text(statusDetail(at: context.date))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(1)
                        .monospacedDigit()
                }

                BrewFlowRail(isFlowing: isFlowing, isPaused: policy == .pausedForLowBattery)
            }
            .foregroundStyle(.white)
            .padding(16)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary(at: context.date))
        }
        .background {
            LinearGradient(
                colors: [
                    ChorreadorPalette.volcanicSoil,
                    policy == .pausedForLowBattery
                        ? ChorreadorPalette.coffeeWood
                        : ChorreadorPalette.coffeeCherry,
                    ChorreadorPalette.rainforest
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var statusLabel: String {
        switch policy {
        case .inactive: return "READY"
        case .protectingSystem, .protectingSystemAndDisplay:
            if automaticPour { return "FLOWING" }
            return "POURING"
        case .pausedForLowBattery: return "RESTING"
        }
    }

    private var statusTitle: String {
        switch policy {
        case .inactive:
            return "Ready to pour"
        case .protectingSystem, .protectingSystemAndDisplay:
            if !detectedNames.isEmpty {
                return detectedNames.joined(separator: " + ")
            }
            return "Manual pour"
        case .pausedForLowBattery:
            return "Cuidando la batería"
        }
    }

    private func statusDetail(at date: Date) -> String {
        switch policy {
        case .inactive:
            return automaticDetectionEnabled
                ? "Watching quietly for local agents"
                : "Normal macOS sleep behavior"
        case .protectingSystem, .protectingSystemAndDisplay:
            let duration = elapsedText(since: pourStartedAt, now: date)
            return displayMayRest
                ? "\(duration) · Display may rest"
                : "\(duration) · Display stays awake"
        case .pausedForLowBattery:
            return "The pour resumes when power returns"
        }
    }

    private func accessibilitySummary(at date: Date) -> String {
        "Chorreador, \(statusLabel.lowercased()). \(statusTitle). \(statusDetail(at: date))."
    }

    private func elapsedText(since startDate: Date?, now: Date) -> String {
        guard let startDate else { return "Just started" }
        let totalMinutes = max(0, Int(now.timeIntervalSince(startDate)) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        if minutes > 0 { return "\(minutes)m" }
        return "Less than a minute"
    }
}

private struct BrewFlowRail: View {
    let isFlowing: Bool
    let isPaused: Bool

    private var flowColor: Color {
        if isPaused { return ChorreadorPalette.parchment.opacity(0.72) }
        return isFlowing ? ChorreadorPalette.parchment : .white.opacity(0.24)
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: isFlowing ? "drop.fill" : "drop")
                .font(.caption)

            Capsule()
                .fill(flowColor)
                .frame(height: 2)

            Image(systemName: "cup.and.saucer.fill")
                .font(.caption)
        }
        .foregroundStyle(flowColor)
        .accessibilityHidden(true)
    }
}

private struct AutoPourControl: View {
    @Binding var isEnabled: Bool
    let detectedNames: [String]

    var body: some View {
        Toggle(isOn: $isEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Auto-pour", systemImage: "sparkles")
                    .font(.body.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(ChorreadorPalette.rainforest)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var subtitle: String {
        if !isEnabled { return "Agent detection is off" }
        if detectedNames.isEmpty { return "Watching five built-in agents" }
        return "Detected: \(detectedNames.joined(separator: " + "))"
    }
}

private struct PourActions: View {
    @Binding var manualPourEnabled: Bool
    let timerEndDate: Date?
    let startTimer: (BrewTimerOption) -> Void
    let cancelTimer: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggleManualPour) {
                Label(
                    manualPourEnabled ? "Stop manual" : "Manual pour",
                    systemImage: manualPourEnabled ? "stop.fill" : "hand.tap.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(manualPourEnabled ? ChorreadorPalette.coffeeCherry : ChorreadorPalette.rainforest)

            TimerMenu(
                endDate: timerEndDate,
                startTimer: startTimer,
                cancelTimer: cancelTimer
            )
        }
        .controlSize(.large)
        .padding(16)
    }

    private func toggleManualPour() {
        manualPourEnabled.toggle()
    }
}

private struct TimerMenu: View {
    let endDate: Date?
    let startTimer: (BrewTimerOption) -> Void
    let cancelTimer: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Menu {
                ForEach(BrewTimerOption.allCases) { option in
                    Button(option.title) {
                        startTimer(option)
                    }
                }

                if endDate != nil {
                    Divider()
                    Button("Stop timer", role: .destructive, action: cancelTimer)
                }
            } label: {
                Label(timerLabel(at: context.date), systemImage: "timer")
            }
            .fixedSize()
            .accessibilityLabel(timerAccessibilityLabel(at: context.date))
        }
    }

    private func timerLabel(at date: Date) -> String {
        guard let endDate else { return "Timer" }
        let minutes = max(1, Int(ceil(endDate.timeIntervalSince(date) / 60)))
        return "\(minutes)m"
    }

    private func timerAccessibilityLabel(at date: Date) -> String {
        guard endDate != nil else { return "Start a brew timer" }
        return "Brew timer, \(timerLabel(at: date)) remaining"
    }
}

private struct MenuFooter: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Hecho en Costa Rica")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer()

            settingsControl

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var settingsControl: some View {
        Button("Settings…", action: openSettings)
            .buttonStyle(.plain)
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

enum ChorreadorPalette {
    static let volcanicSoil = Color(red: 0.14, green: 0.067, blue: 0.043) // #24110B
    static let coffeeWood = Color(red: 0.54, green: 0.25, blue: 0.11) // #8A3F1D
    static let coffeeCherry = Color(red: 0.66, green: 0.22, blue: 0.17) // #A9372B
    static let rainforest = Color(red: 0.14, green: 0.39, blue: 0.29) // #236349
    static let parchment = Color(red: 0.96, green: 0.87, blue: 0.75) // #F4DFC0
}
