import SwiftUI

@main
struct ChorreadorApp: App {
    @StateObject private var powerManager = PowerManager()

    var body: some Scene {
        MenuBarExtra {
            ChorreadorMenuView(powerManager: powerManager)
        } label: {
            Label("Chorreador", systemImage: "drop.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
