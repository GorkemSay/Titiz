import AppKit
import CoreText
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
            button.image = makeMenuBarTemplateIcon()
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

    func showPopover() {
        guard let button = statusItem?.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        focusEditor()
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

    func popoverDidClose(_ notification: Notification) {
        state.resetUpdateCheckIfIdle()
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

    private func makeMenuBarTemplateIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let squirclePath = RoundedRectangle(cornerRadius: 3.375, style: .continuous)
            .path(in: CGRect(x: 1.5, y: 1.5, width: 15.0, height: 15.0))
            .cgPath
        let glyphPath = Self.makeTemplateTPath(centeredAt: CGPoint(x: 9.0, y: 8.9), targetHeight: 9.4)

        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            defer { ctx.endTransparencyLayer() }

            ctx.setShouldAntialias(true)
            ctx.setAllowsAntialiasing(true)
            ctx.addPath(squirclePath)
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fillPath()

            if let glyphPath {
                ctx.setBlendMode(.destinationOut)
                ctx.addPath(glyphPath)
                ctx.setFillColor(CGColor(gray: 0, alpha: 1))
                ctx.fillPath()
            }

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Titiz"
        return image
    }

    private static func makeTemplateTPath(centeredAt center: CGPoint, targetHeight: CGFloat) -> CGPath? {
        let baseFont = NSFont.systemFont(ofSize: 44, weight: .bold)
        let font: NSFont
        if let descriptor = baseFont.fontDescriptor.withDesign(.serif),
           let serifFont = NSFont(descriptor: descriptor, size: 44) {
            font = serifFont
        } else if let georgia = NSFont(name: "Georgia-Bold", size: 44) {
            font = georgia
        } else {
            font = baseFont
        }

        let ctFont = font as CTFont
        var chars: [UniChar] = Array("T".utf16)
        var glyphs: [CGGlyph] = [0]
        guard CTFontGetGlyphsForCharacters(ctFont, &chars, &glyphs, chars.count),
              let rawPath = CTFontCreatePathForGlyph(ctFont, glyphs[0], nil) else {
            return nil
        }

        let bounds = rawPath.boundingBoxOfPath
        guard bounds.height > 0 else { return nil }

        let scale = targetHeight / bounds.height
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: center.x, y: center.y)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -bounds.midX, y: -bounds.midY)
        return rawPath.copy(using: &transform)
    }
}
