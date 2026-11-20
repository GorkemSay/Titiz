import AppKit
import SwiftUI
import TitizCore

@main
struct TitizApp: App {
    @NSApplicationDelegateAdaptor(TitizAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class TitizAppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the utility strictly in the menu bar (`LSUIElement` behavior even during `swift run`).
        NSApplication.shared.setActivationPolicy(.accessory)
        menuBarController.start()
    }
}
