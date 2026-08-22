import AppKit
import SwiftUI

struct ChorreadorMenuView: View {
    @ObservedObject var powerManager: PowerManager
    @ObservedObject var journal: PourJournal

    init(powerManager: PowerManager) {
        self.powerManager = powerManager
        self.journal = powerManager.journal
    }

    private var isFlowing: Bool {
        powerManager.policy == .protectingSystem
            || powerManager.policy == .protectingSystemAndDisplay
    }

    var body: some View {
        VStack(spacing: 0) {
            BrewStatusHeader(
                policy: powerManager.policy,
                automaticPour: powerManager.isAutomaticallyProtecting,
                detectedNames: powerManager.detectedProcessDisplayNames,
                pourStartedAt: powerManager.pourStartedAt,
                displayMayRest: powerManager.letDisplaySleep,
                automaticDetectionEnabled: powerManager.automaticDetectionEnabled,
                manualPourEnabled: powerManager.protectionEnabled,
                brewTimerEndDate: powerManager.brewTimerEndDate,
                sleepCount: journal.openRecord?.interruptions.count ?? 0
            )

            if !isFlowing,
               let lastPour = journal.lastCompletedRecord,
               let endedAt = lastPour.endedAt,
               Date().timeIntervalSince(endedAt) < 86_400 {
                LastPourRow(record: lastPour)
            }

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

            MenuFooter {
                SettingsWindowController.shared.show(powerManager: powerManager)
            }
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
    let manualPourEnabled: Bool
    let brewTimerEndDate: Date?
    let sleepCount: Int

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

                    statusChip
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
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var statusChip: some View {
        HStack(spacing: 5) {
            if isFlowing {
                PulsingDot()
            }
            Text(statusLabel)
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .tracking(0.7)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isFlowing ? ChorreadorPalette.parchment.opacity(0.22) : Color.white.opacity(0.14),
            in: Capsule()
        )
    }

    private var gradientColors: [Color] {
        switch policy {
        case .inactive:
            return [
                ChorreadorPalette.volcanicSoil,
                ChorreadorPalette.duskWood,
                ChorreadorPalette.nightForest
            ]
        case .pausedForLowBattery:
            return [
                ChorreadorPalette.volcanicSoil,
                ChorreadorPalette.coffeeWood,
                ChorreadorPalette.rainforest
            ]
        case .protectingSystem, .protectingSystemAndDisplay:
            return [
                ChorreadorPalette.volcanicSoil,
                ChorreadorPalette.coffeeCherry,
                ChorreadorPalette.rainforest
            ]
        }
    }

    private var statusLabel: String {
        switch policy {
        case .inactive: return automaticDetectionEnabled ? "WATCHING" : "IDLE"
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
            return "Keeping your Mac awake"
        case .pausedForLowBattery:
            return "Cuidando la batería"
        }
    }

    private func statusDetail(at date: Date) -> String {
        switch policy {
        case .inactive:
            return automaticDetectionEnabled
                ? "Watching for agents · Mac sleeps normally"
                : "Auto-pour is off · Mac sleeps normally"
        case .protectingSystem, .protectingSystemAndDisplay:
            let display = displayMayRest ? "display may rest" : "display stays awake"
            var detail = "\(pourSourceDescription(at: date)) · \(display)"
            if sleepCount > 0 {
                detail += " · slept \(sleepCount)×"
            }
            return detail
        case .pausedForLowBattery:
            return "Paused at \(PowerManager.lowBatteryThreshold)% · resumes when power returns"
        }
    }

    private func pourSourceDescription(at date: Date) -> String {
        if !detectedNames.isEmpty {
            return "\(detectedNames.joined(separator: " + ")) · \(elapsedText(since: pourStartedAt, now: date))"
        }
        if manualPourEnabled {
            return "Manual pour · \(elapsedText(since: pourStartedAt, now: date))"
        }
        if let brewTimerEndDate {
            return "Brew timer · \(brewTimerRemainingText(until: brewTimerEndDate, now: date)) left"
        }
        return "Manual pour"
    }

    private func accessibilitySummary(at date: Date) -> String {
        "Chorreador, \(statusLabel.lowercased()). \(statusTitle). \(statusDetail(at: date))."
    }

    private func elapsedText(since startDate: Date?, now: Date) -> String {
        guard let startDate else { return "just started" }
        let totalMinutes = max(0, Int(now.timeIntervalSince(startDate)) / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        if minutes > 0 { return "\(minutes)m" }
        return "under 1m"
    }
}

private struct PulsingDot: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let phase = (sin(timeline.date.timeIntervalSinceReferenceDate * (2 * .pi / 1.8)) + 1) / 2
            Circle()
                .fill(ChorreadorPalette.parchment)
                .frame(width: 5, height: 5)
                .opacity(0.35 + 0.6 * phase)
        }
        .accessibilityHidden(true)
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
            Image(systemName: isFlowing || isPaused ? "drop.fill" : "drop")
                .font(.caption)

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isFlowing)) { timeline in
                Canvas { context, size in
                    let midY = size.height / 2
                    let track = Path(
                        roundedRect: CGRect(x: 0, y: midY - 1, width: size.width, height: 2),
                        cornerRadius: 1
                    )
                    let showsDrops = isFlowing || isPaused
                    context.fill(track, with: .color(flowColor.opacity(showsDrops ? 0.35 : 1)))

                    guard showsDrops else { return }

                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let dropCount = 4
                    for index in 0..<dropCount {
                        let phase = Double(index) / Double(dropCount)
                        let progress = isPaused
                            ? phase + 0.12
                            : (time * 0.22 + phase).truncatingRemainder(dividingBy: 1)
                        let fade = min(1, min(progress, 1 - progress) * 5)
                        let radius: CGFloat = 2.4
                        let drop = CGRect(
                            x: progress * size.width - radius,
                            y: midY - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        context.fill(Path(ellipseIn: drop), with: .color(flowColor.opacity(fade)))
                    }
                }
            }
            .frame(height: 7)

            Image(systemName: "cup.and.saucer.fill")
                .font(.caption)
        }
        .foregroundStyle(flowColor)
        .accessibilityHidden(true)
    }
}

private struct LastPourRow: View {
    let record: PourRecord

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(record.interruptions.isEmpty ? Color.secondary : .orange)

            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .help(record.sources.joined(separator: " + "))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Last pour: \(summary)")
    }

    private var icon: String {
        if !record.interruptions.isEmpty { return "moon.zzz.fill" }
        switch record.endReason {
        case .batteryPause: return "battery.25"
        case .appQuit: return "exclamationmark.circle"
        case .finished, nil: return "checkmark.circle"
        }
    }

    private var summary: String {
        let duration = brewDurationText(record.duration(asOf: Date()))
        var text = "Last pour \(duration)"
        if !record.interruptions.isEmpty {
            let lost = brewDurationText(record.totalSleepLost)
            text += " · slept \(record.interruptions.count)× (\(lost) lost)"
        } else {
            switch record.endReason {
            case .batteryPause: text += " · paused for battery"
            case .appQuit: text += " · cut short"
            case .finished, nil: text += " · clean finish"
            }
        }
        return text
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
        return brewTimerRemainingText(until: endDate, now: date)
    }

    private func timerAccessibilityLabel(at date: Date) -> String {
        guard endDate != nil else { return "Start a brew timer" }
        return "Brew timer, \(timerLabel(at: date)) remaining"
    }
}

private struct MenuFooter: View {
    let openSettings: () -> Void

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
}

private func brewTimerRemainingText(until endDate: Date, now: Date) -> String {
    let totalMinutes = max(1, Int(ceil(endDate.timeIntervalSince(now) / 60)))
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
    return "\(minutes)m"
}

enum ChorreadorPalette {
    static let volcanicSoil = Color(red: 0.14, green: 0.067, blue: 0.043) // #24110B
    static let coffeeWood = Color(red: 0.54, green: 0.25, blue: 0.11) // #8A3F1D
    static let coffeeCherry = Color(red: 0.66, green: 0.22, blue: 0.17) // #A9372B
    static let rainforest = Color(red: 0.14, green: 0.39, blue: 0.29) // #236349
    static let parchment = Color(red: 0.96, green: 0.87, blue: 0.75) // #F4DFC0
    static let duskWood = Color(red: 0.24, green: 0.15, blue: 0.10) // #3D2619
    static let nightForest = Color(red: 0.09, green: 0.16, blue: 0.13) // #17291F
}
