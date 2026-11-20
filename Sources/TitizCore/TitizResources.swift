import Foundation

/// Shared cached linguistic resources loaded once per process to keep proofreading latency < 10 ms.
public final class TitizResources: Sendable {
    public static let shared: TitizResources = {
        do {
            return try loadBundled()
        } catch {
            fatalError("Failed to load bundled TitizCore resources: \(error)")
        }
    }()

    public let dictionary: HunspellDictionary
    public let gpaScorer: GPAScorer
    public let englishWordlist: EnglishWordlist
    public let frequencyTable: TurkishFrequencyTable
    public let gazetteer: EntityGazetteer
    public let ruleCatalog: SpellingRuleCatalog

    public init(
        dictionary: HunspellDictionary,
        gpaScorer: GPAScorer,
        englishWordlist: EnglishWordlist,
        frequencyTable: TurkishFrequencyTable,
        gazetteer: EntityGazetteer,
        ruleCatalog: SpellingRuleCatalog
    ) {
        self.dictionary = dictionary
        self.gpaScorer = gpaScorer
        self.englishWordlist = englishWordlist
        self.frequencyTable = frequencyTable
        self.gazetteer = gazetteer
        self.ruleCatalog = ruleCatalog
    }

    public static func loadBundled() throws -> TitizResources {
        let dict = try HunspellDictionary.loadBundledTurkish()
        let gpa = try GPAScorer.loadBundled()
        let en = try EnglishWordlist.loadBundled()
        let freq = try TurkishFrequencyTable.loadBundled()
        let gazetteer = try EntityGazetteer.loadBundled()
        let ruleCatalog = try SpellingRuleCatalog.loadBundled()

        return TitizResources(
            dictionary: dict,
            gpaScorer: gpa,
            englishWordlist: en,
            frequencyTable: freq,
            gazetteer: gazetteer,
            ruleCatalog: ruleCatalog
        )
    }
}
