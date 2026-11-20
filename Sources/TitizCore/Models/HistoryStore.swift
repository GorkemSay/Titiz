import Foundation

/// Single recent proofreading entry persisted in `history.json` (last 5 corrections).
public struct HistoryEntry: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let originalText: String
    public let correctedText: String
    public let mode: CorrectionMode
    public let editCount: Int
    public let elapsedMilliseconds: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        originalText: String,
        correctedText: String,
        mode: CorrectionMode,
        editCount: Int,
        elapsedMilliseconds: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.originalText = originalText
        self.correctedText = correctedText
        self.mode = mode
        self.editCount = editCount
        self.elapsedMilliseconds = elapsedMilliseconds
        self.createdAt = createdAt
    }
}

/// Thread-safe, disk-persisted store retaining the most recent 5 corrections (`~/Library/Application Support/Titiz/history.json`).
public final class HistoryStore: @unchecked Sendable {
    public static let maxEntries = 5

    private struct PersistedPayload: Codable {
        let schemaVersion: String
        let entries: [HistoryEntry]
    }

    private let lock = NSLock()
    private let storageURL: URL?
    private var storedEntries: [HistoryEntry]

    public static func defaultStorageURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Titiz", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }

    public init(storageURL: URL? = nil, entries: [HistoryEntry] = []) {
        self.storageURL = storageURL
        self.storedEntries = Array(entries.prefix(Self.maxEntries))
    }

    public static func load(from storageURL: URL = defaultStorageURL()) throws -> HistoryStore {
        let store = HistoryStore(storageURL: storageURL, entries: [])
        try store.reload()
        return store
    }

    public static func loadDefaultOrEmpty() -> HistoryStore {
        (try? load(from: defaultStorageURL())) ?? HistoryStore(storageURL: defaultStorageURL())
    }

    public var entries: [HistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storedEntries
    }

    /// Records a new correction at the top of the list (capping at 5 entries) and persists immediately.
    @discardableResult
    public func record(
        originalText: String,
        correctedText: String,
        mode: CorrectionMode,
        editCount: Int,
        elapsedMilliseconds: Int
    ) throws -> HistoryEntry {
        lock.lock()
        defer { lock.unlock() }

        let entry = HistoryEntry(
            originalText: originalText,
            correctedText: correctedText,
            mode: mode,
            editCount: editCount,
            elapsedMilliseconds: elapsedMilliseconds
        )

        // Collapse immediate identical re-runs so history stays useful.
        storedEntries.removeAll { $0.correctedText == correctedText && $0.mode == mode }
        storedEntries.insert(entry, at: 0)
        if storedEntries.count > Self.maxEntries {
            storedEntries = Array(storedEntries.prefix(Self.maxEntries))
        }

        try persistLocked()
        return entry
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }

        storedEntries = []
        try persistLocked()
    }

    public func reload() throws {
        lock.lock()
        defer { lock.unlock() }

        guard let storageURL, FileManager.default.fileExists(atPath: storageURL.path) else {
            storedEntries = []
            return
        }

        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(PersistedPayload.self, from: data)
        storedEntries = Array(payload.entries.prefix(Self.maxEntries))
    }

    private func persistLocked() throws {
        guard let storageURL else { return }
        let dir = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let payload = PersistedPayload(schemaVersion: "1.0.0", entries: storedEntries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: storageURL, options: .atomic)
    }
}
