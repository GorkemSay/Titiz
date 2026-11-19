import CHunspell
import Foundation

/// Errors thrown when loading a `HunspellDictionary`.
public enum HunspellDictionaryError: Error, Sendable, Equatable {
    case bundledResourcesMissing
    case failedToLoad(affPath: String, dicPath: String)
}

/// Thread-safe Swift wrapper around an embedded C++ Hunspell dictionary instance.
///
/// - Important: Rejection by `contains(_:)` never implies a word is erroneous on its own
///   (e.g., due to Hunspell's 2-fold affix stripping limit or legitimate OOV/foreign terms).
public final class HunspellDictionary: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: OpaquePointer

    /// Loads the bundled Turkish (`tr_TR`) dictionary from `TitizCore` module resources.
    public static func loadBundledTurkish() throws -> HunspellDictionary {
        guard
            let affURL = Bundle.module.url(forResource: "tr_TR", withExtension: "aff"),
            let dicURL = Bundle.module.url(forResource: "tr_TR", withExtension: "dic")
        else {
            throw HunspellDictionaryError.bundledResourcesMissing
        }

        return try HunspellDictionary(affPath: affURL.path, dicPath: dicURL.path)
    }

    /// Initializes a dictionary instance from explicit `.aff` and `.dic` file paths.
    public init(affPath: String, dicPath: String) throws {
        guard let created = affPath.withCString({ affPtr in
            dicPath.withCString { dicPtr in
                chunspell_create(affPtr, dicPtr)
            }
        }) else {
            throw HunspellDictionaryError.failedToLoad(affPath: affPath, dicPath: dicPath)
        }

        self.handle = created
    }

    deinit {
        chunspell_destroy(handle)
    }

    /// Returns `true` if Hunspell accepts the given word (after UTF-8 NFC normalization).
    public func contains(_ word: String) -> Bool {
        guard !word.isEmpty else {
            return false
        }

        let normalized = word.precomposedStringWithCanonicalMapping
        return lock.withLock {
            normalized.withCString { wordPtr in
                chunspell_spell(handle, wordPtr)
            }
        }
    }

    /// Returns Hunspell spelling suggestions for the given word (after UTF-8 NFC normalization).
    public func suggestions(for word: String) -> [String] {
        guard !word.isEmpty else {
            return []
        }

        let normalized = word.precomposedStringWithCanonicalMapping
        return lock.withLock {
            var rawSuggestions: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
            let count = normalized.withCString { wordPtr in
                chunspell_suggest(handle, wordPtr, &rawSuggestions)
            }
            defer {
                chunspell_free_list(handle, rawSuggestions, count)
            }

            guard count > 0, let rawSuggestions else {
                return []
            }

            var results: [String] = []
            results.reserveCapacity(Int(count))
            for index in 0..<Int(count) {
                if let cString = rawSuggestions[index] {
                    results.append(String(cString: cString))
                }
            }
            return results
        }
    }

    /// Adds a word dynamically to this runtime dictionary session.
    @discardableResult
    public func addRuntimeWord(_ word: String) -> Bool {
        guard !word.isEmpty else {
            return false
        }

        let normalized = word.precomposedStringWithCanonicalMapping
        return lock.withLock {
            normalized.withCString { wordPtr in
                chunspell_add(handle, wordPtr) == 0
            }
        }
    }
}
