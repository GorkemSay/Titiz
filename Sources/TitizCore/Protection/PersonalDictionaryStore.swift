import Foundation

/// Single user-defined entry in the Personal Dictionary ("Bu adı hep koru", Tier 1).
public struct PersonalDictionaryEntry: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let id: UUID
    public let term: String
    public let isCaseSensitive: Bool
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        term: String,
        isCaseSensitive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.term = term.precomposedStringWithCanonicalMapping
        self.isCaseSensitive = isCaseSensitive
        self.createdAt = createdAt
    }
}

/// Immutable compiled view of Personal Dictionary entries for lock-free pipeline execution.
public struct PersonalDictionarySnapshot: Sendable, Equatable {
    public static let empty = PersonalDictionarySnapshot(entries: [])

    public let entries: [PersonalDictionaryEntry]
    private let exactSingleTerms: Set<String>
    private let foldedSingleTerms: Set<String>
    private let exactPhraseTrie: MultiWordEntityTrie
    private let foldedPhraseTrie: MultiWordEntityTrie

    public init(entries: [PersonalDictionaryEntry]) {
        self.entries = entries

        var exactSingle: Set<String> = []
        var foldedSingle: Set<String> = []
        var exactPhrases: [String] = []
        var foldedPhrases: [String] = []

        for entry in entries {
            let trimmed = PersonalDictionaryStore.normalizeTerm(entry.term)
            guard !trimmed.isEmpty else { continue }

            let lexed = StructuralLexer.tokenize(TextNormalizer.normalize(trimmed))
            let nonWhitespaceCount = lexed.reduce(into: 0) { count, tok in
                if tok.kind != .whitespace { count += 1 }
            }

            if nonWhitespaceCount <= 1 {
                if entry.isCaseSensitive {
                    exactSingle.insert(trimmed)
                } else {
                    foldedSingle.insert(TurkishLocale.lowercased(trimmed))
                }
            } else {
                if entry.isCaseSensitive {
                    exactPhrases.append(trimmed)
                } else {
                    foldedPhrases.append(trimmed)
                }
            }
        }

        self.exactSingleTerms = exactSingle
        self.foldedSingleTerms = foldedSingle
        self.exactPhraseTrie = MultiWordEntityTrie(phrases: exactPhrases, caseSensitive: true)
        self.foldedPhraseTrie = MultiWordEntityTrie(phrases: foldedPhrases, caseSensitive: false)
    }

    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// Returns `true` if a single-token stem matches any single-word Tier 1 entry.
    public func matchesSingleTokenStem(_ stem: String) -> Bool {
        guard !stem.isEmpty else { return false }
        let nfc = stem.precomposedStringWithCanonicalMapping
        if exactSingleTerms.contains(nfc) {
            return true
        }
        if !foldedSingleTerms.isEmpty {
            return foldedSingleTerms.contains(TurkishLocale.lowercased(nfc))
        }
        return false
    }

    /// Applies Tier 1 Personal Dictionary protection (multi-word longest match first, then single-word).
    /// Always takes precedence over built-in Tier 2 / Tier 3 entity lists.
    public func apply(to tokens: inout [Token]) {
        guard !entries.isEmpty else { return }

        if !exactPhraseTrie.isEmpty {
            exactPhraseTrie.apply(
                to: &tokens,
                tier: .tier1PersonalDictionary,
                reasonPrefix: "Personal dictionary phrase",
                overrideExistingEntityOrWordTier0: true
            )
        }

        if !foldedPhraseTrie.isEmpty {
            foldedPhraseTrie.apply(
                to: &tokens,
                tier: .tier1PersonalDictionary,
                reasonPrefix: "Personal dictionary phrase",
                overrideExistingEntityOrWordTier0: true
            )
        }

        for index in tokens.indices {
            if tokens[index].protection?.tier == .tier1PersonalDictionary {
                continue
            }
            switch tokens[index].kind {
            case .word, .apostropheWord:
                if matchesSingleTokenStem(tokens[index].stemText) {
                    tokens[index].protection = ProtectionInfo(
                        tier: .tier1PersonalDictionary,
                        reason: "Personal dictionary entry: \(tokens[index].stemText)",
                        structuralKind: tokens[index].protection?.structuralKind
                    )
                }
            case .punctuation, .whitespace, .protectedSpan:
                break
            }
        }
    }
}

/// Thread-safe, disk-persisted Tier 1 Personal Dictionary store (`~/Library/Application Support/Titiz/personal_dictionary.json`).
public final class PersonalDictionaryStore: @unchecked Sendable {
    private struct PersistedPayload: Codable {
        let schemaVersion: String
        let entries: [PersonalDictionaryEntry]
    }

    private let lock = NSLock()
    private let storageURL: URL?
    private var storedEntries: [PersonalDictionaryEntry]
    private var compiledSnapshot: PersonalDictionarySnapshot

    /// Default storage location under the current user's Application Support directory.
    public static func defaultStorageURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("Titiz", isDirectory: true)
            .appendingPathComponent("personal_dictionary.json", isDirectory: false)
    }

    /// Creates a store backed by `storageURL` (pass `nil` for strictly in-memory ephemeral use).
    public init(storageURL: URL? = nil, entries: [PersonalDictionaryEntry] = []) {
        self.storageURL = storageURL
        let normalized = Self.deduplicate(entries)
        self.storedEntries = normalized
        self.compiledSnapshot = PersonalDictionarySnapshot(entries: normalized)
    }

    /// Loads entries from `storageURL` if the file exists, or initializes an empty store cleanly.
    public static func load(from storageURL: URL = defaultStorageURL()) throws -> PersonalDictionaryStore {
        let store = PersonalDictionaryStore(storageURL: storageURL, entries: [])
        try store.reload()
        return store
    }

    /// Convenience factory for shared app runtime usage, falling back to an empty store if disk read fails.
    public static func loadDefaultOrEmpty() -> PersonalDictionaryStore {
        (try? load(from: defaultStorageURL())) ?? PersonalDictionaryStore(storageURL: defaultStorageURL())
    }

    public var entries: [PersonalDictionaryEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storedEntries
    }

    /// Returns a lock-free immutable snapshot for fast evaluation inside `TitizEngine`.
    public var snapshot: PersonalDictionarySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return compiledSnapshot
    }

    /// Adds or updates a single or multi-word protected term and persists immediately.
    @discardableResult
    public func add(term: String, isCaseSensitive: Bool = true) throws -> PersonalDictionaryEntry? {
        let normalizedTerm = Self.normalizeTerm(term)
        guard !normalizedTerm.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }

        let entry = PersonalDictionaryEntry(term: normalizedTerm, isCaseSensitive: isCaseSensitive)
        if let existingIdx = storedEntries.firstIndex(where: {
            $0.isCaseSensitive == isCaseSensitive &&
            Self.termsEqual($0.term, normalizedTerm, caseSensitive: isCaseSensitive)
        }) {
            return storedEntries[existingIdx]
        }

        storedEntries.append(entry)
        storedEntries = Self.deduplicate(storedEntries)
        compiledSnapshot = PersonalDictionarySnapshot(entries: storedEntries)
        try persistLocked()
        return entry
    }

    /// Removes entries matching `id` and persists immediately.
    public func remove(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        let beforeCount = storedEntries.count
        storedEntries.removeAll { $0.id == id }
        guard storedEntries.count != beforeCount else { return }

        compiledSnapshot = PersonalDictionarySnapshot(entries: storedEntries)
        try persistLocked()
    }

    /// Removes entries matching `term` (exact NFC normalized match) and persists immediately.
    public func remove(term: String) throws {
        let normalizedTerm = Self.normalizeTerm(term)
        guard !normalizedTerm.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        let beforeCount = storedEntries.count
        storedEntries.removeAll { $0.term == normalizedTerm }
        guard storedEntries.count != beforeCount else { return }

        compiledSnapshot = PersonalDictionarySnapshot(entries: storedEntries)
        try persistLocked()
    }

    /// Replaces the entire dictionary with `entries` and persists immediately.
    public func replaceAll(with entries: [PersonalDictionaryEntry]) throws {
        lock.lock()
        defer { lock.unlock() }

        storedEntries = Self.deduplicate(entries)
        compiledSnapshot = PersonalDictionarySnapshot(entries: storedEntries)
        try persistLocked()
    }

    /// Reloads entries from `storageURL` (if present on disk) and updates the snapshot immediately.
    public func reload() throws {
        lock.lock()
        defer { lock.unlock() }

        guard let storageURL, FileManager.default.fileExists(atPath: storageURL.path) else {
            storedEntries = []
            compiledSnapshot = .empty
            return
        }

        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(PersistedPayload.self, from: data)
        storedEntries = Self.deduplicate(payload.entries)
        compiledSnapshot = PersonalDictionarySnapshot(entries: storedEntries)
    }

    // MARK: - Private Helpers

    static func normalizeTerm(_ raw: String) -> String {
        let trimmed = raw
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .joined(separator: " ")
    }

    private static func termsEqual(_ lhs: String, _ rhs: String, caseSensitive: Bool) -> Bool {
        if caseSensitive {
            return lhs == rhs
        }
        return TurkishLocale.lowercased(lhs) == TurkishLocale.lowercased(rhs)
    }

    private static func deduplicate(_ entries: [PersonalDictionaryEntry]) -> [PersonalDictionaryEntry] {
        var result: [PersonalDictionaryEntry] = []
        var seen: Set<String> = []

        for entry in entries {
            let term = normalizeTerm(entry.term)
            guard !term.isEmpty else { continue }
            let key = "\(entry.isCaseSensitive ? "cs" : "ci"):\(entry.isCaseSensitive ? term : TurkishLocale.lowercased(term))"
            if seen.insert(key).inserted {
                result.append(
                    PersonalDictionaryEntry(
                        id: entry.id,
                        term: term,
                        isCaseSensitive: entry.isCaseSensitive,
                        createdAt: entry.createdAt
                    )
                )
            }
        }
        return result
    }

    private func persistLocked() throws {
        guard let storageURL else { return }
        let directory = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let payload = PersistedPayload(schemaVersion: "1.0.0", entries: storedEntries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: storageURL, options: .atomic)
    }
}
