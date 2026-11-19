import AppKit
import SwiftUI
import TitizCore

@main
struct TitizApp: App {
    var body: some Scene {
        MenuBarExtra("Titiz", systemImage: "text.badge.checkmark") {
            TitizPlaceholderView()
        }
        .menuBarExtraStyle(.window)
    }
}

private struct TitizPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Titiz")
                .font(.headline)

            Text("Çevrimdışı Türkçe yazım ve karakter yardımcısı")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Text("Faz 0 başlangıç iskeleti (Sürüm \(TitizEngine.version))")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Çıkış") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
