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
                    state.subpanel = .editor
                } label: {
                    Label("Düzenleyiciye Dön", systemImage: "chevron.left")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderless)

                Spacer()

                Text("Ayarlar ve Kişisel Sözlük")
                    .font(.headline)

                Spacer()

                Button("Çıkış") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .font(.caption)
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
                    .buttonStyle(.borderedProminent)
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
                .frame(maxHeight: 145)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Titiz \(TitizEngine.version) · %100 Çevrimdışı")
                    .font(.caption.weight(.semibold))

                Text("Motor: CHunspell \(TitizEngine.hunspellBridgeVersion) · Sözlük: tdd-ai/hunspell-tr (MPL-2.0) · GPA: Deniz Yüret (MIT) · Varlıklar: Wikidata (CC0 1.0) · Frekanslar: Leipzig Corpora (CC BY 4.0).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func addTerm() {
        let candidate = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        state.protectTermAndReevaluate(candidate, isCaseSensitive: newTermCaseSensitive)
        newTerm = ""
    }
}
