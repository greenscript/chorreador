import SwiftUI

@main
struct ChorreadorApp: App {
    @StateObject private var powerManager = PowerManager()

    var body: some Scene {
        MenuBarExtra {
            ChorreadorMenuView(powerManager: powerManager)
        } label: {
            MenuBarStatusIcon(powerManager: powerManager)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarStatusIcon: View {
    @ObservedObject var powerManager: PowerManager

    var body: some View {
        Image(systemName: symbolName)
            .accessibilityLabel(accessibilityLabel)
    }

    private var symbolName: String {
        switch powerManager.policy {
        case .protectingSystem, .protectingSystemAndDisplay: return "drop.fill"
        case .pausedForLowBattery: return "drop.halffull"
        case .inactive: return "drop"
        }
    }

    private var accessibilityLabel: String {
        switch powerManager.policy {
        case .protectingSystem, .protectingSystemAndDisplay: return "Chorreador, keeping your Mac awake"
        case .pausedForLowBattery: return "Chorreador, resting for battery care"
        case .inactive: return "Chorreador, idle"
        }
    }
}
