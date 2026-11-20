import SwiftUI
import TitizCore

/// Primary 500 px wide menu bar popover container hosting header controls, editor canvas,
/// selection "Bu adı hep koru" pill, edit-detail popover, footer, history, and settings.
struct MainPopoverView: View {
    @Bindable var state: TitizAppState
    let onRegisterTextView: (TitizNSTextView) -> Void

    private var isInspectingBinding: Binding<Bool> {
        Binding(
            get: { state.inspectionTarget != nil },
            set: { if !$0 { state.inspectionTarget = nil } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch state.subpanel {
            case .editor:
                editorScreen
            case .history:
                HistoryView(state: state)
            case .settings:
                SettingsView(state: state)
            }
        }
        .padding(16)
        .frame(width: 500)
    }

    @ViewBuilder
    private var editorScreen: some View {
        headerBar

        ZStack(alignment: .topLeading) {
            TitizTextEditor(
                text: $state.text,
                appliedEdits: state.appliedEdits,
                ambiguousSuggestions: state.ambiguousSuggestions,
                onTextEdited: { state.handleManualTextChange($0) },
                onSelectionChanged: { state.selectedUTF16Range = $0 },
                onInspect: { state.inspectionTarget = $0 },
                onProtectSelection: { state.protectTermAndReevaluate($0) },
                onRunCorrection: { state.runCorrection() },
                onCopyAll: { state.copyToPasteboard() },
                onRegisterTextView: onRegisterTextView
            )
            .frame(height: 220)

            if state.text.isEmpty {
                Text("Türkçe metninizi buraya yapıştırın (⌘V)...")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 15)
                    .padding(.top, 11)
                    .allowsHitTesting(false)
            }

            if let target = state.inspectionTarget {
                let anchor = anchorRect(for: target)
                Color.clear
                    .frame(width: max(1, anchor.width), height: max(1, anchor.height))
                    .offset(x: anchor.origin.x, y: anchor.origin.y)
                    .allowsHitTesting(false)
                    .popover(isPresented: isInspectingBinding, arrowEdge: .bottom) {
                        EditDetailPopoverView(
                            target: target,
                            ruleCatalog: state.engine.resources.ruleCatalog,
                            onApplyEditAlternative: { state.applyAlternative($0, for: $1) },
                            onRevertEdit: { state.revertEdit($0) },
                            onApplySuggestionCandidate: { state.applySuggestionCandidate($0, for: $1) },
                            onProtectTerm: { state.protectTermAndReevaluate($0) }
                        )
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            if !state.text.isEmpty {
                Button {
                    state.clearEditor()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .padding(8)
                .help("Metni Temizle")
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let selection = state.selectedPhraseCandidate {
                Button {
                    state.protectTermAndReevaluate(selection)
                } label: {
                    Label("Bu adı hep koru: “\(truncated(selection))”", systemImage: "shield.lefthalf.filled")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .titizGlassPill(interactive: true)
                .padding(8)
            }
        }
        .titizSurfaceCard(cornerRadius: 12)

        if let notice = state.statusNotice {
            Text(notice)
                .font(.caption)
                .foregroundStyle(.secondary)
                .transition(.opacity)
        }

        footerBar
    }

    @ViewBuilder
    private var headerBar: some View {
        TitizGlassGroup(spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "text.badge.checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.tint)

                    Text("Titiz")
                        .font(.system(.headline, weight: .semibold))
                }

                Spacer()

                modePicker

                HStack(spacing: 4) {
                    Button {
                        state.historyEntries = state.historyStore.entries
                        state.subpanel = .history
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .titizGlassPill(interactive: true)
                    .help("Son 5 Düzeltme")

                    Button {
                        state.personalEntries = state.engine.personalDictionaryStore.entries
                        state.subpanel = .settings
                    } label: {
                        Image(systemName: "gearshape")
                            .frame(width: 26, height: 24)
                    }
                    .buttonStyle(.borderless)
                    .titizGlassPill(interactive: true)
                    .help("Ayarlar ve Kişisel Sözlük")
                }
            }
        }
    }

    @ViewBuilder
    private var modePicker: some View {
        HStack(spacing: 2) {
            modeChip(.combined, title: "Düzelt")
            modeChip(.character, title: "Karakter")
            modeChip(.spelling, title: "Yazım")
        }
        .padding(3)
        .titizGlassPill(interactive: true)
    }

    @ViewBuilder
    private func modeChip(_ mode: CorrectionMode, title: String) -> some View {
        let isSelected = state.selectedMode == mode
        Button {
            state.selectedMode = mode
        } label: {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? Color(nsColor: .controlAccentColor).opacity(0.16) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var footerBar: some View {
        TitizGlassGroup(spacing: 8) {
            HStack(spacing: 10) {
                Text(state.formattedStatusSummary)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    state.copyToPasteboard()
                } label: {
                    Label(state.didJustCopy ? "Kopyalandı" : "Kopyala",
                          systemImage: state.didJustCopy ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .titizGlassPill(interactive: true)
                .disabled(state.text.isEmpty)
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button {
                    state.runCorrection()
                } label: {
                    Text(primaryButtonTitle)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Capsule())
                .disabled(state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var primaryButtonTitle: String {
        switch state.selectedMode {
        case .combined: return "Düzelt"
        case .character: return "Karakterleri Düzelt"
        case .spelling: return "Yazımı Düzelt"
        }
    }

    private func anchorRect(for target: InspectionTarget) -> CGRect {
        let raw: CGRect
        switch target {
        case let .edit(_, anchorRect):
            raw = anchorRect
        case let .suggestion(_, anchorRect):
            raw = anchorRect
        }
        let clampedX = min(max(8, raw.origin.x), 430)
        let clampedY = min(max(8, raw.origin.y), 200)
        return CGRect(x: clampedX, y: clampedY, width: max(12, raw.width), height: max(16, raw.height))
    }

    private func truncated(_ text: String) -> String {
        if text.count <= 22 { return text }
        return String(text.prefix(20)) + "…"
    }
}
