import AppKit
import SwiftUI
import TitizCore

/// AppKit-backed text editor providing reliable `⌘V` / `⌘C` / `⌘A` / `⌘Z` handling inside
/// an `LSUIElement` menu bar window, semantic inline diff highlights, click-to-inspect rects,
/// and selection context menu for "Bu adı hep koru".
struct TitizTextEditor: NSViewRepresentable {
    @Binding var text: String
    let appliedEdits: [Edit]
    let ambiguousSuggestions: [AmbiguousTokenSuggestion]
    let onTextEdited: (String) -> Void
    let onSelectionChanged: (NSRange) -> Void
    let onInspect: (InspectionTarget) -> Void
    let onProtectSelection: (String) -> Void
    let onRunCorrection: () -> Void
    let onCopyAll: () -> Void
    let onRegisterTextView: (TitizNSTextView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let textView = TitizNSTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4.5
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]

        textView.onMouseClickAtUTF16Index = { [weak coordinator = context.coordinator, weak scrollView] charIndex in
            guard let coordinator, let scrollView else { return false }
            return coordinator.handleClick(atUTF16Index: charIndex, in: scrollView)
        }
        textView.onProtectTerm = { [weak coordinator = context.coordinator] term in
            coordinator?.parent.onProtectSelection(term)
        }
        textView.onRunCorrectionShortcut = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onRunCorrection()
        }
        textView.onCopyShortcut = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onCopyAll()
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        onRegisterTextView(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? TitizNSTextView else { return }

        if textView.string != text {
            context.coordinator.isProgrammaticUpdate = true
            let previousSelection = textView.selectedRange()
            textView.string = text
            let maxLen = (text as NSString).length
            let clamped = NSRange(
                location: min(previousSelection.location, maxLen),
                length: min(previousSelection.length, max(0, maxLen - min(previousSelection.location, maxLen)))
            )
            textView.setSelectedRange(clamped)
            context.coordinator.isProgrammaticUpdate = false
        }

        applyHighlights(to: textView)
    }

    private func applyHighlights(to textView: TitizNSTextView) {
        guard let storage = textView.textStorage else { return }
        let fullLength = storage.length
        guard fullLength > 0 else { return }

        let fullRange = NSRange(location: 0, length: fullLength)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4.5

        storage.beginEditing()
        storage.setAttributes([
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ], range: fullRange)

        for edit in appliedEdits {
            let nsRange = NSRange(location: edit.correctedRange.location, length: edit.correctedRange.length)
            guard nsRange.location >= 0, NSMaxRange(nsRange) <= fullLength, nsRange.length > 0 else { continue }
            storage.addAttributes([
                .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.15),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: NSColor.systemGreen.withAlphaComponent(0.75),
            ], range: nsRange)
        }

        for suggestion in ambiguousSuggestions {
            let nsRange = NSRange(location: suggestion.correctedRange.location, length: suggestion.correctedRange.length)
            guard nsRange.location >= 0, NSMaxRange(nsRange) <= fullLength, nsRange.length > 0 else { continue }
            storage.addAttributes([
                .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.12),
                .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                .underlineColor: NSColor.systemOrange.withAlphaComponent(0.8),
            ], range: nsRange)
        }
        storage.endEditing()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TitizTextEditor
        weak var textView: TitizNSTextView?
        weak var scrollView: NSScrollView?
        var isProgrammaticUpdate = false

        init(parent: TitizTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammaticUpdate, let tv = textView else { return }
            parent.onTextEdited(tv.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isProgrammaticUpdate, let tv = textView else { return }
            parent.onSelectionChanged(tv.selectedRange())
        }

        func handleClick(atUTF16Index index: Int, in scrollView: NSScrollView) -> Bool {
            guard let tv = textView else { return false }

            for edit in parent.appliedEdits {
                let start = edit.correctedRange.location
                let end = edit.correctedRange.upperBound
                if index >= start && index < end {
                    let rect = boundingRect(for: NSRange(location: start, length: edit.correctedRange.length), in: tv, scrollView: scrollView)
                    parent.onInspect(.edit(edit, anchorRect: rect))
                    return true
                }
            }

            for suggestion in parent.ambiguousSuggestions {
                let start = suggestion.correctedRange.location
                let end = suggestion.correctedRange.upperBound
                if index >= start && index < end {
                    let rect = boundingRect(for: NSRange(location: start, length: suggestion.correctedRange.length), in: tv, scrollView: scrollView)
                    parent.onInspect(.suggestion(suggestion, anchorRect: rect))
                    return true
                }
            }

            return false
        }

        private func boundingRect(for nsRange: NSRange, in textView: NSTextView, scrollView: NSScrollView) -> CGRect {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return .zero
            }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: nsRange, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            return textView.convert(rect, to: scrollView)
        }
    }
}

/// Custom `NSTextView` subclass enabling click-to-inspect highlighted diffs,
/// right-click "Bu adı hep koru", and shortcut equivalents (`⌘↩`, `⌘⇧C`).
final class TitizNSTextView: NSTextView {
    var onMouseClickAtUTF16Index: ((Int) -> Bool)?
    var onProtectTerm: ((String) -> Void)?
    var onRunCorrectionShortcut: (() -> Void)?
    var onCopyShortcut: (() -> Void)?

    private var mouseDownLocation: NSPoint = .zero

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = convert(event.locationInWindow, from: nil)
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)

        let upPoint = convert(event.locationInWindow, from: nil)
        let dragDistance = hypot(upPoint.x - mouseDownLocation.x, upPoint.y - mouseDownLocation.y)

        // Only inspect when it is a clean click (zero selection drag) inside a highlighted edit/suggestion.
        if dragDistance <= 3.0, selectedRange().length == 0 {
            let charIndex = characterIndexForInsertion(at: upPoint)
            if charIndex < (string as NSString).length {
                _ = onMouseClickAtUTF16Index?(charIndex)
            }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let baseMenu = super.menu(for: event) ?? NSMenu()
        let sel = selectedRange()
        if sel.length > 0 {
            let raw = (string as NSString).substring(with: sel)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.contains(where: \.isNewline), trimmed.count <= 80 {
                let protectItem = NSMenuItem(
                    title: "Bu adı hep koru: “\(trimmed)”",
                    action: #selector(protectSelectedMenuItem(_:)),
                    keyEquivalent: ""
                )
                protectItem.target = self
                protectItem.representedObject = trimmed
                baseMenu.insertItem(NSMenuItem.separator(), at: 0)
                baseMenu.insertItem(protectItem, at: 0)
            }
        }
        return baseMenu
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags == .command, (event.keyCode == 36 || event.keyCode == 76) {
            onRunCorrectionShortcut?()
            return true
        }

        if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "c" {
            onCopyShortcut?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    @objc private func protectSelectedMenuItem(_ sender: NSMenuItem) {
        guard let term = sender.representedObject as? String else { return }
        onProtectTerm?(term)
    }
}
