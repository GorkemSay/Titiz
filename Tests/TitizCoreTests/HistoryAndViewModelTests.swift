import Foundation
import Testing
@testable import TitizCore

@Suite("HistoryStore Persistence")
struct HistoryStoreTests {
    @Test("HistoryStore caps entries at 5, deduplicates identical runs, and persists across reloads")
    func historyCapAndPersistence() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TitizHistoryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("history.json")
        let store = HistoryStore(storageURL: url)

        for i in 1...7 {
            try store.record(
                originalText: "girdi \(i)",
                correctedText: "çıktı \(i)",
                mode: .combined,
                editCount: i,
                elapsedMilliseconds: 3
            )
        }

        let current = store.entries
        #expect(current.count == 5)
        #expect(current.first?.correctedText == "çıktı 7")
        #expect(current.last?.correctedText == "çıktı 3")

        // Reloading from disk recovers the exact 5 persisted entries
        let reloaded = try HistoryStore.load(from: url)
        #expect(reloaded.entries.map(\.correctedText) == current.map(\.correctedText))

        // Duplicate identical output + mode collapses cleanly to top without shrinking unique count below 5
        try reloaded.record(
            originalText: "girdi 3",
            correctedText: "çıktı 3",
            mode: .combined,
            editCount: 3,
            elapsedMilliseconds: 2
        )
        #expect(reloaded.entries.count == 5)
        #expect(reloaded.entries.first?.correctedText == "çıktı 3")

        try reloaded.clear()
        #expect(reloaded.entries.isEmpty)
        let afterClear = try HistoryStore.load(from: url)
        #expect(afterClear.entries.isEmpty)
    }
}
