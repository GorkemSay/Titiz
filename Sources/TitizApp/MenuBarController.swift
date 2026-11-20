import AppKit
import SwiftUI
import TitizCore

/// AppKit menu bar status item + popover coordinator providing instant keyboard focus
/// and standard macOS Edit menu key equivalents (`⌘V`, `⌘C`, `⌘X`, `⌘A`, `⌘Z`) inside an `LSUIElement` utility.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let state: TitizAppState
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private weak var editorTextView: TitizNSTextView?

    init(state: TitizAppState = TitizAppState()) {
        self.state = state
        super.init()
    }

    func start() {
        installStandardEditMenu()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: "Titiz")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Titiz — Çevrimdışı Türkçe Düzeltici"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        self.statusItem = item

        let rootView = MainPopoverView(state: state) { [weak self] textView in
            self?.editorTextView = textView
        }
        let hostingController = NSHostingController(rootView: rootView)
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // Warm bundled Hunspell/entity/frequency resources in background so first correction is instant.
        Task.detached(priority: .userInitiated) {
            _ = TitizResources.shared
        }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            focusEditor()
        }
    }

    func popoverDidShow(_ notification: Notification) {
        focusEditor()
    }

    private func focusEditor() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let window = self.popover.contentViewController?.view.window {
                window.makeKey()
                if self.state.subpanel == .editor, let textView = self.editorTextView {
                    window.makeFirstResponder(textView)
                }
            }
        }
    }

    private func installStandardEditMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Titiz'den Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem(title: "Düzen", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Düzen")
        editMenu.addItem(withTitle: "Geri Al", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Yinele", action: Selector(("redo:")), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Kes", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Kopyala", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Yapıştır", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Tümünü Seç", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
