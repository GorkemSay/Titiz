import SwiftUI
import TitizCore

/// Displays the last 5 local proofreading runs with single-click copy or reload into the editor.
struct HistoryView: View {
    @Bindable var state: TitizAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    state.subpanel = .editor
                } label: {
                    Label("Düzenleyiciye Dön", systemImage: "chevron.left")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("Son 5 Düzeltme")
                    .font(.headline)

                Spacer()

                if !state.historyEntries.isEmpty {
                    Button("Temizle") {
                        state.clearHistory()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }

            Divider()

            if state.historyEntries.isEmpty {
                ContentUnavailableView(
                    "Henüz Geçmiş Yok",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Yaptığınız son 5 düzeltme Mac'inizde yerel olarak burada saklanır.")
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(state.historyEntries) { entry in
                            historyRow(entry)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 280)
            }
        }
    }

    @ViewBuilder
    private func historyRow(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.correctedText)
                .font(.callout)
                .lineLimit(2)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Text(modeLabel(entry.mode))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text("\(entry.editCount) düzeltme · \(entry.elapsedMilliseconds) ms")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Yükle") {
                    state.loadFromHistory(entry)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("Kopyala") {
                    state.copyToPasteboard(entry.correctedText)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(10)
        .titizSurfaceCard(cornerRadius: 10)
    }

    private func modeLabel(_ mode: CorrectionMode) -> String {
        switch mode {
        case .combined: return "Düzelt"
        case .character: return "Karakter"
        case .spelling: return "Yazım"
        }
    }
}
