import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(powerManager: PowerManager) {
        let settingsWindow = window ?? makeWindow(powerManager: powerManager)

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(powerManager: PowerManager) -> NSWindow {
        let hostingController = NSHostingController(
            rootView: ChorreadorSettingsView(powerManager: powerManager)
        )
        let settingsWindow = NSWindow(contentViewController: hostingController)
        settingsWindow.title = "Chorreador Settings"
        settingsWindow.styleMask = [.titled, .closable, .miniaturizable]
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.collectionBehavior = [.moveToActiveSpace]
        settingsWindow.center()
        window = settingsWindow
        return settingsWindow
    }
}
