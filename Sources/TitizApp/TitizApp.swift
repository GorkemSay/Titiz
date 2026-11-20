import AppKit

@main
@MainActor
enum TitizAppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = TitizAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class TitizAppDelegate: NSObject, NSApplicationDelegate {
    private let menuBarController = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the utility strictly in the menu bar (`LSUIElement` behavior even during `swift run`)
        // without opening a blank SwiftUI Settings window on launch.
        NSApplication.shared.setActivationPolicy(.accessory)
        menuBarController.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBarController.showPopover()
        return false
    }
}
