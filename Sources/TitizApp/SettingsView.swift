import AppKit
import SwiftUI
import TitizCore

/// Settings sub-screen managing the Personal Dictionary (`personal_dictionary.json`) and license attributions.
struct SettingsView: View {
    @Bindable var state: TitizAppState
    @State private var newTerm: String = ""
    @State private var newTermCaseSensitive: Bool = true
    @State private var searchQuery: String = ""

    private var filteredEntries: [PersonalDictionaryEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return state.personalEntries }
        let lowered = TurkishLocale.lowercased(query)
        return state.personalEntries.filter {
            TurkishLocale.lowercased($0.term).contains(lowered)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    state.resetUpdateCheckIfIdle()
                    state.subpanel = .editor
                } label: {
                    Label("Düzenleyiciye Dön", systemImage: "chevron.left")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                Spacer()

                Text("Ayarlar ve Kişisel Sözlük")
                    .font(.headline)

                Spacer()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Kişisel Sözlük (“Bu adı hep koru”)")
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 8) {
                    TextField("Örn: MaviKutu veya Yeni Proje X", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addTerm() }

                    Button("Ekle") {
                        addTerm()
                    }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(TitizPrimaryButtonStyle(cornerRadius: 6, horizontalPadding: 10, verticalPadding: 4))
                    .controlSize(.small)
                    .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Toggle("Büyük/küçük harf duyarlı", isOn: $newTermCaseSensitive)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Sözlükte ara...", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
            }

            if filteredEntries.isEmpty {
                Text(state.personalEntries.isEmpty
                     ? "Henüz korunan özel ad yok. Düzenleyicide bir sözcüğü seçip ekleyebilirsiniz."
                     : "Aramayla eşleşen kayıt bulunamadı.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredEntries) { entry in
                            HStack(spacing: 8) {
                                Text(entry.term)
                                    .font(.callout.weight(.medium))

                                if entry.isCaseSensitive {
                                    Text("Harf duyarlı")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button {
                                    state.removePersonalEntry(entry)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("Kişisel Sözlük'ten kaldır")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .titizSurfaceCard(cornerRadius: 8)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }

            Divider()

            updatesSection

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Titiz v\(AppUpdater.currentVersionString) · %100 Çevrimdışı")
                    .font(.caption.weight(.semibold))

                Text("Motor: CHunspell \(TitizEngine.hunspellBridgeVersion) · Sözlük: tdd-ai/hunspell-tr (MPL-2.0) · GPA: Deniz Yüret (MIT) · Varlıklar: Wikidata (CC0 1.0) · Frekanslar: Leipzig Corpora (CC BY 4.0).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear {
            state.resetUpdateCheckIfIdle()
        }
    }

    @ViewBuilder
    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Güncellemeler")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                switch state.updateState {
                case .idle:
                    HStack(spacing: 8) {
                        Text("Mevcut sürüm: v\(AppUpdater.currentVersionString)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Güncellemeleri Denetle") {
                            state.checkForUpdates()
                        }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(TitizPrimaryButtonStyle(cornerRadius: 6, horizontalPadding: 10, verticalPadding: 4))
                        .controlSize(.small)
                    }

                case .checking:
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Güncellemeler denetleniyor...")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }

                case let .upToDate(current):
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)

                        Text("Uygulama güncel (v\(current))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.primary)

                        Spacer()
                    }

                case let .available(update):
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Yeni sürüm mevcut: v\(update.version.description)")
                                .font(.caption.weight(.semibold))

                            Link("Sürüm Notları", destination: update.releasePageURL)
                                .font(.caption2)
                        }

                        Spacer()

                        Button("Yükle") {
                            state.installAvailableUpdate(update)
                        }
                        .font(.subheadline.weight(.medium))
                        .buttonStyle(TitizPrimaryButtonStyle(cornerRadius: 6, horizontalPadding: 10, verticalPadding: 4))
                        .controlSize(.small)
                    }

                case let .downloading(version, progress):
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("v\(version) indiriliyor...")
                                .font(.caption.weight(.medium))
                            Spacer()
                            if let progress {
                                Text("\(Int((progress * 100).rounded()))%")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let progress {
                            ProgressView(value: progress, total: 1.0)
                                .tint(TitizBrandColors.burgundy)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                case let .installing(version):
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        Text("v\(version) kuruluyor, Titiz yeniden başlatılacak...")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()
                    }

                case let .failed(message):
                    HStack(spacing: 8) {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 6)

                        Button("Tekrar Dene") {
                            state.checkForUpdates()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(10)
            .titizSurfaceCard(cornerRadius: 10)
        }
    }

    private func addTerm() {
        let candidate = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        state.protectTermAndReevaluate(candidate, isCaseSensitive: newTermCaseSensitive)
        newTerm = ""
    }
}
