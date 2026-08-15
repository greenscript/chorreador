import SwiftUI

@main
struct ChorreadorApp: App {
    @StateObject private var powerManager = PowerManager()

    var body: some Scene {
        MenuBarExtra {
            ChorreadorMenuView(powerManager: powerManager)
        } label: {
            Label("Chorreador", systemImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        switch powerManager.policy {
        case .protectingSystem, .protectingSystemAndDisplay:
            return "drop.fill"
        case .pausedForLowBattery:
            return "leaf.fill"
        case .inactive:
            return "drop"
        }
    }
}
