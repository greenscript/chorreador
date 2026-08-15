import AppKit
import SwiftUI

struct ChorreadorMenuView: View {
    @ObservedObject var powerManager: PowerManager
    @State private var customProcessName = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero

                VStack(spacing: 14) {
                    protectionCard
                    brewTimerCard
                    automationCard
                    customAgentCard
                    batteryCard
                    footer
                }
                .padding(16)
            }
        }
        .frame(width: 390)
        .frame(maxHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            powerManager.refreshLaunchAtLoginStatus()
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Palette.volcanicSoil, Palette.coffeeCherry, Palette.rainforest],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            dropWatermark

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Palette.parchment)
                    Text("CHORREADOR")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .tracking(1.8)
                    Spacer()
                    statusPill
                }

                Text(statusTitle)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(statusDetail)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(2)
            }
            .foregroundStyle(.white)
            .padding(18)
        }
        .frame(height: 150)
        .clipped()
    }

    private var dropWatermark: some View {
        ZStack {
            Image(systemName: "drop.fill")
                .font(.system(size: 120, weight: .bold))
                .foregroundStyle(.white.opacity(0.055))
            Image(systemName: "drop.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(Palette.parchment.opacity(0.13))
                .offset(x: -72, y: 36)
        }
        .offset(x: 145, y: -34)
    }

    private var protectionCard: some View {
        VStack(spacing: 0) {
            settingRow(
                icon: "hand.tap.fill",
                title: "Manual pour",
                subtitle: "Keep your Mac awake on demand",
                isOn: $powerManager.protectionEnabled
            )

            Divider().padding(.leading, 46)

            settingRow(
                icon: "sparkles",
                title: "Auto-pour for agents",
                subtitle: agentDetectionSubtitle,
                isOn: $powerManager.automaticDetectionEnabled
            )

            Divider().padding(.leading, 46)

            settingRow(
                icon: "display",
                title: "Let the display rest",
                subtitle: "Recommended for long sessions",
                isOn: $powerManager.letDisplaySleep,
                disabled: !powerManager.protectionConfigured
            )
        }
        .background(Palette.soilWash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.coffeeWood.opacity(0.20), lineWidth: 1)
        }
    }

    private var batteryCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: batteryIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(batteryColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(batteryTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text(powerManager.battery.isOnBattery ? "Flowing on battery" : "Plugged in and ready")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $powerManager.lowBatteryGuardEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Palette.rainforest)
            }

            Text("Stop the pour at \(PowerManager.lowBatteryThreshold)% on battery to prevent an unexpected deep discharge.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Palette.parchment.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var brewTimerCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.coffeeCherry)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Brew timer")
                        .font(.system(size: 13, weight: .semibold))
                    Text(brewTimerSubtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if powerManager.brewTimerEndDate != nil {
                    Button("Stop") {
                        powerManager.cancelBrewTimer()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if powerManager.brewTimerEndDate == nil {
                HStack(spacing: 8) {
                    ForEach(BrewTimerOption.allCases) { option in
                        Button(option.title) {
                            powerManager.startBrewTimer(option)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(Palette.coffeeWood)
                    }
                }
                .padding(.leading, 34)
            }
        }
        .padding(14)
        .background(Palette.parchment.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var automationCard: some View {
        VStack(spacing: 0) {
            settingRow(
                icon: "power",
                title: "Launch at login",
                subtitle: powerManager.launchAtLoginNeedsApproval
                    ? "Approval required in System Settings"
                    : "Be ready before the agents wake up",
                isOn: Binding(
                    get: { powerManager.launchAtLoginEnabled },
                    set: { powerManager.setLaunchAtLoginEnabled($0) }
                )
            )

            Divider().padding(.leading, 46)

            settingRow(
                icon: "bell.badge.fill",
                title: "Pour notifications",
                subtitle: "Only agent transitions and battery pauses",
                isOn: Binding(
                    get: { powerManager.notificationsEnabled },
                    set: { powerManager.setNotificationsEnabled($0) }
                )
            )
        }
        .background(Palette.soilWash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.coffeeWood.opacity(0.20), lineWidth: 1)
        }
    }

    private var customAgentCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.rainforest)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom processes")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add an executable name, like aider")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                TextField("Executable name", text: $customProcessName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addCustomProcess)

                Button(action: addCustomProcess) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Palette.rainforest)
                .disabled(customProcessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !powerManager.customProcessNames.isEmpty {
                FlowLayout(spacing: 7) {
                    ForEach(powerManager.customProcessNames, id: \.self) { processName in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(powerManager.detectedCustomProcesses.contains(processName)
                                    ? Palette.rainforest
                                    : Color.secondary.opacity(0.35))
                                .frame(width: 6, height: 6)
                            Text(processName)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            Button {
                                powerManager.removeCustomProcess(processName)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Palette.parchment.opacity(0.28), in: Capsule())
                    }
                }
            }
        }
        .padding(14)
        .background(Palette.parchment.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Label("Hecho en Costa Rica · local-only", systemImage: "heart.fill")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }

    private func settingRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        disabled: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(disabled ? Color.secondary : Palette.rainforest)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Palette.rainforest)
        }
        .padding(13)
        .opacity(disabled ? 0.5 : 1)
        .disabled(disabled)
    }

    private var statusPill: some View {
        Text(statusLabel.uppercased())
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.8)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.white.opacity(0.14), in: Capsule())
    }

    private var statusLabel: String {
        switch powerManager.policy {
        case .inactive: return "Listo"
        case .protectingSystem:
            if powerManager.isAutomaticallyProtecting { return "Chorreando" }
            return powerManager.brewTimerEndDate == nil ? "Manual" : "Timed"
        case .protectingSystemAndDisplay: return "Full pour"
        case .pausedForLowBattery: return "Reposando"
        }
    }

    private var statusTitle: String {
        switch powerManager.policy {
        case .inactive: return "Listo para chorrear"
        case .protectingSystem:
            if powerManager.isAutomaticallyProtecting { return automaticBrewTitle }
            return powerManager.brewTimerEndDate == nil
                ? "Manual pour is active"
                : "Timed pour is active"
        case .protectingSystemAndDisplay: return "Full pour is active"
        case .pausedForLowBattery: return "Cuidando la batería"
        }
    }

    private var statusDetail: String {
        switch powerManager.policy {
        case .inactive:
            return powerManager.automaticDetectionEnabled
                ? "Watching quietly for five agent runtimes."
                : "macOS controls sleep normally until you start a pour."
        case .protectingSystem:
            if powerManager.isAutomaticallyProtecting {
                return "\(activeDurationText) · The display may rest."
            }
            return "\(activeDurationText) · The display may rest normally."
        case .protectingSystemAndDisplay:
            return "Both idle system sleep and display sleep are blocked."
        case .pausedForLowBattery:
            return "The pour resumes automatically after connecting power."
        }
    }

    private var agentDetectionSubtitle: String {
        guard powerManager.automaticDetectionEnabled else {
            return "Watch for supported coding agents"
        }
        guard !powerManager.detectedProcessDisplayNames.isEmpty else {
            return "Waiting for a supported agent"
        }
        return "Flowing: \(detectedAgentNames)"
    }

    private var automaticBrewTitle: String {
        powerManager.detectedProcessDisplayNames.count == 1
            ? "\(detectedAgentNames) keeps flowing"
            : "Your agents keep flowing"
    }

    private var detectedAgentNames: String {
        powerManager.detectedProcessDisplayNames
            .joined(separator: " + ")
    }

    private var activeDurationText: String {
        guard let startedAt = powerManager.pourStartedAt else { return "Just started" }
        let elapsed = max(0, Int(powerManager.now.timeIntervalSince(startedAt)))
        let hours = elapsed / 3_600
        let minutes = (elapsed % 3_600) / 60
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        if minutes > 0 { return "\(minutes)m" }
        return "Less than a minute"
    }

    private var brewTimerSubtitle: String {
        guard let endDate = powerManager.brewTimerEndDate else {
            return "Keep the Mac awake for a fixed pour"
        }
        let remaining = max(0, Int(endDate.timeIntervalSince(powerManager.now)))
        let totalMinutes = Int(ceil(Double(remaining) / 60.0))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return String(format: "%dh %02dm remaining", hours, minutes) }
        return "\(minutes)m remaining"
    }

    private func addCustomProcess() {
        powerManager.addCustomProcess(customProcessName)
        customProcessName = ""
    }

    private var batteryTitle: String {
        guard let percentage = powerManager.battery.percentage else {
            return "Battery care"
        }
        return "Battery care · \(percentage)%"
    }

    private var batteryIcon: String {
        guard let percentage = powerManager.battery.percentage else { return "battery.100" }
        if powerManager.battery.isCharging { return "battery.100.bolt" }
        if percentage <= 25 { return "battery.25" }
        if percentage <= 50 { return "battery.50" }
        if percentage <= 75 { return "battery.75" }
        return "battery.100"
    }

    private var batteryColor: Color {
        guard let percentage = powerManager.battery.percentage else { return .secondary }
        return percentage <= PowerManager.lowBatteryThreshold && powerManager.battery.isOnBattery
            ? .orange
            : Palette.rainforest
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 340
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return (CGSize(width: width, height: y + lineHeight), points)
    }
}

private enum Palette {
    static let volcanicSoil = Color(red: 0.12, green: 0.045, blue: 0.025)
    static let coffeeCherry = Color(red: 0.48, green: 0.10, blue: 0.07)
    static let rainforest = Color(red: 0.08, green: 0.34, blue: 0.24)
    static let coffeeWood = Color(red: 0.72, green: 0.38, blue: 0.16)
    static let parchment = Color(red: 0.95, green: 0.85, blue: 0.67)
    static let soilWash = Color(red: 0.40, green: 0.19, blue: 0.08).opacity(0.075)
}
