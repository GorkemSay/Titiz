import AppKit
import Foundation
import Observation
import TitizCore

/// Active inspection target when the user clicks an inline highlight in the editor.
enum InspectionTarget: Equatable {
    case edit(Edit, anchorRect: CGRect)
    case suggestion(AmbiguousTokenSuggestion, anchorRect: CGRect)
}

/// Primary sub-screen rendered inside the menu bar popover.
enum PopoverSubpanel: Equatable {
    case editor
    case history
    case settings
}

@MainActor
@Observable
final class TitizAppState {
    private static let clock = ContinuousClock()

    let engine: TitizEngine
    let historyStore: HistoryStore

    var text: String = ""
    var selectedMode: CorrectionMode = .combined
    var subpanel: PopoverSubpanel = .editor

    var appliedEdits: [Edit] = []
    var ambiguousSuggestions: [AmbiguousTokenSuggestion] = []
    var lastElapsedMs: Int?
    var didJustCopy: Bool = false

    var selectedUTF16Range: NSRange = NSRange(location: 0, length: 0)
    var inspectionTarget: InspectionTarget?

    var personalEntries: [PersonalDictionaryEntry] = []
    var historyEntries: [HistoryEntry] = []
    var statusNotice: String?

    /// Original input text captured when the user ran "Düzelt" so adding a term to the
    /// Personal Dictionary immediately re-evaluates cleanly against the source input.
    private var sourceTextBeforeCorrection: String?
    private var copyFeedbackTask: Task<Void, Never>?

    init(
        engine: TitizEngine = TitizEngine(personalDictionaryStore: PersonalDictionaryStore.loadDefaultOrEmpty()),
        historyStore: HistoryStore = HistoryStore.loadDefaultOrEmpty()
    ) {
        self.engine = engine
        self.historyStore = historyStore
        self.personalEntries = engine.personalDictionaryStore.entries
        self.historyEntries = historyStore.entries
    }

    /// Trimmed phrase currently highlighted by the user in the editor (if valid for "Bu adı hep koru").
    var selectedPhraseCandidate: String? {
        guard selectedUTF16Range.length > 0 else { return nil }
        let nsString = text as NSString
        guard selectedUTF16Range.location >= 0,
              selectedUTF16Range.location + selectedUTF16Range.length <= nsString.length else {
            return nil
        }
        let raw = nsString.substring(with: selectedUTF16Range)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline), trimmed.count <= 80 else {
            return nil
        }
        return trimmed
    }

    var formattedStatusSummary: String {
        guard let elapsed = lastElapsedMs else {
            return "Hazır"
        }
        let count = appliedEdits.count
        if count == 0 {
            return "Değişiklik yok · \(elapsed) ms"
        }
        return "\(count) düzeltme · \(elapsed) ms"
    }

    /// Runs deterministic proofreading across the active editor text.
    func runCorrection() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            appliedEdits = []
            ambiguousSuggestions = []
            lastElapsedMs = nil
            inspectionTarget = nil
            return
        }

        let input = text
        sourceTextBeforeCorrection = input

        var result: CorrectionResult!
        let duration = Self.clock.measure {
            result = engine.correct(input, mode: selectedMode)
        }
        let elapsedMs = max(1, Int(Double(duration.components.seconds) * 1_000.0 + Double(duration.components.attoseconds) / 1e15))

        text = result.correctedText
        appliedEdits = result.edits
        ambiguousSuggestions = result.ambiguousSuggestions
        lastElapsedMs = elapsedMs
        inspectionTarget = nil
        statusNotice = nil

        if !result.edits.isEmpty || !result.correctedText.isEmpty {
            _ = try? historyStore.record(
                originalText: result.originalText,
                correctedText: result.correctedText,
                mode: result.mode,
                editCount: result.edits.count,
                elapsedMilliseconds: elapsedMs
            )
            historyEntries = historyStore.entries
        }
    }

    /// Called when the user edits text directly inside the editor; invalidates stale highlights.
    func handleManualTextChange(_ updated: String) {
        guard updated != text else { return }
        text = updated
        if !appliedEdits.isEmpty || !ambiguousSuggestions.isEmpty || inspectionTarget != nil {
            appliedEdits = []
            ambiguousSuggestions = []
            inspectionTarget = nil
            sourceTextBeforeCorrection = nil
        }
        lastElapsedMs = nil
    }

    /// Reverts a single applied edit independently back to its original text.
    func revertEdit(_ edit: Edit) {
        guard replaceUTF16Range(edit.correctedRange, expectedSlice: edit.replacement, with: edit.original) else {
            return
        }
        let delta = edit.original.utf16.count - edit.replacement.utf16.count
        appliedEdits.removeAll { $0.id == edit.id }
        shiftHighlights(afterUTF16Location: edit.correctedRange.upperBound, by: delta)
        inspectionTarget = nil
    }

    /// Swaps an applied edit to one of its ranked Bucket 2 alternatives (or restores original).
    func applyAlternative(_ candidate: String, for edit: Edit) {
        guard replaceUTF16Range(edit.correctedRange, expectedSlice: edit.replacement, with: candidate) else {
            return
        }
        let delta = candidate.utf16.count - edit.replacement.utf16.count
        let oldUpper = edit.correctedRange.upperBound

        let updatedAlternatives = ([edit.replacement] + edit.alternatives).filter { $0 != candidate }
        let updatedEdit = Edit(
            id: edit.id,
            origin: edit.origin,
            ruleID: edit.ruleID,
            bucket: edit.bucket,
            confidence: edit.confidence,
            original: edit.original,
            replacement: candidate,
            alternatives: updatedAlternatives,
            originalRange: edit.originalRange,
            correctedRange: UTF16Range(location: edit.correctedRange.location, length: candidate.utf16.count)
        )

        if let idx = appliedEdits.firstIndex(where: { $0.id == edit.id }) {
            appliedEdits[idx] = updatedEdit
        }
        shiftHighlights(afterUTF16Location: oldUpper, by: delta, excludingEditID: edit.id)
        inspectionTarget = nil
    }

    /// Applies one of the ranked candidates attached to a conservatively preserved Bucket 2 suggestion.
    func applySuggestionCandidate(_ candidate: String, for suggestion: AmbiguousTokenSuggestion) {
        guard replaceUTF16Range(suggestion.correctedRange, expectedSlice: suggestion.original, with: candidate) else {
            return
        }
        let delta = candidate.utf16.count - suggestion.original.utf16.count
        let oldUpper = suggestion.correctedRange.upperBound

        ambiguousSuggestions.removeAll {
            $0.original == suggestion.original && $0.correctedRange == suggestion.correctedRange
        }
        shiftHighlights(afterUTF16Location: oldUpper, by: delta)

        let remainingAlternatives = ([suggestion.original] + suggestion.candidates).filter { $0 != candidate }
        let promotedEdit = Edit(
            origin: .character,
            ruleID: "char.bucket2",
            bucket: .bucket2,
            confidence: 0.75,
            original: suggestion.original,
            replacement: candidate,
            alternatives: remainingAlternatives,
            originalRange: suggestion.originalRange,
            correctedRange: UTF16Range(location: suggestion.correctedRange.location, length: candidate.utf16.count)
        )
        appliedEdits.append(promotedEdit)
        appliedEdits.sort { $0.correctedRange.location < $1.correctedRange.location }
        inspectionTarget = nil
    }

    /// Saves `term` into Tier 1 Personal Dictionary (`personal_dictionary.json`) and
    /// immediately re-evaluates the current text so protection applies at once.
    func protectTermAndReevaluate(_ term: String, isCaseSensitive: Bool = true) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            try engine.personalDictionaryStore.add(term: trimmed, isCaseSensitive: isCaseSensitive)
            personalEntries = engine.personalDictionaryStore.entries
            inspectionTarget = nil
            statusNotice = "“\(trimmed)” Kişisel Sözlük'e eklendi"

            if let source = sourceTextBeforeCorrection {
                text = source
                runCorrection()
            } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Re-evaluate editor text so highlights reflect current state cleanly.
                let result = engine.correct(text, mode: selectedMode)
                text = result.correctedText
                appliedEdits = result.edits
                ambiguousSuggestions = result.ambiguousSuggestions
            }
        } catch {
            statusNotice = "Kişisel Sözlük kaydedilemedi"
        }
    }

    func removePersonalEntry(_ entry: PersonalDictionaryEntry) {
        do {
            try engine.personalDictionaryStore.remove(id: entry.id)
            personalEntries = engine.personalDictionaryStore.entries
            if let source = sourceTextBeforeCorrection {
                text = source
                runCorrection()
            }
        } catch {
            statusNotice = "Kayıt silinemedi"
        }
    }

    func copyToPasteboard(_ content: String? = nil) {
        let value = content ?? text
        guard !value.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)

        if content == nil {
            didJustCopy = true
            copyFeedbackTask?.cancel()
            copyFeedbackTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                if !Task.isCancelled {
                    self?.didJustCopy = false
                }
            }
        }
    }

    func loadFromHistory(_ entry: HistoryEntry) {
        text = entry.correctedText
        sourceTextBeforeCorrection = entry.originalText
        selectedMode = entry.mode
        appliedEdits = []
        ambiguousSuggestions = []
        lastElapsedMs = entry.elapsedMilliseconds
        inspectionTarget = nil
        subpanel = .editor
    }

    func clearHistory() {
        try? historyStore.clear()
        historyEntries = historyStore.entries
    }

    func clearEditor() {
        text = ""
        sourceTextBeforeCorrection = nil
        appliedEdits = []
        ambiguousSuggestions = []
        lastElapsedMs = nil
        inspectionTarget = nil
        selectedUTF16Range = NSRange(location: 0, length: 0)
    }

    func ruleMetadata(for ruleID: String) -> SpellingRuleMetadata? {
        if let direct = engine.resources.ruleCatalog.metadata(for: ruleID) {
            return direct
        }
        // Combined edits may join two rule IDs (`char.bucket2+spell.capitalization.sentence_start`).
        if let firstPart = ruleID.split(separator: "+").first {
            return engine.resources.ruleCatalog.metadata(for: String(firstPart))
        }
        return nil
    }

    // MARK: - Private UTF-16 Range Maintenance

    private func replaceUTF16Range(_ range: UTF16Range, expectedSlice: String, with replacement: String) -> Bool {
        let mutable = NSMutableString(string: text)
        guard range.location >= 0, range.upperBound <= mutable.length else {
            return false
        }
        let nsRange = NSRange(location: range.location, length: range.length)
        guard mutable.substring(with: nsRange) == expectedSlice else {
            return false
        }
        mutable.replaceCharacters(in: nsRange, with: replacement)
        text = String(mutable)
        return true
    }

    private func shiftHighlights(
        afterUTF16Location boundary: Int,
        by delta: Int,
        excludingEditID: UUID? = nil
    ) {
        guard delta != 0 else { return }

        appliedEdits = appliedEdits.map { item in
            if item.id == excludingEditID || item.correctedRange.location < boundary {
                return item
            }
            return Edit(
                id: item.id,
                origin: item.origin,
                ruleID: item.ruleID,
                bucket: item.bucket,
                confidence: item.confidence,
                original: item.original,
                replacement: item.replacement,
                alternatives: item.alternatives,
                originalRange: item.originalRange,
                correctedRange: UTF16Range(
                    location: max(0, item.correctedRange.location + delta),
                    length: item.correctedRange.length
                )
            )
        }

        ambiguousSuggestions = ambiguousSuggestions.map { item in
            if item.correctedRange.location < boundary {
                return item
            }
            return AmbiguousTokenSuggestion(
                original: item.original,
                originalRange: item.originalRange,
                correctedRange: UTF16Range(
                    location: max(0, item.correctedRange.location + delta),
                    length: item.correctedRange.length
                ),
                candidates: item.candidates
            )
        }
    }
}
