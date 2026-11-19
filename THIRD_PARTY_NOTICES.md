# Third-Party Notices

Titiz's own source code is licensed under the MIT License (see [LICENSE](LICENSE)).

Titiz bundles and incorporates open-source software, linguistic dictionaries, decision-list models, wordlists, and entity/frequency tables so the application can run 100% offline and deterministically on macOS. Every embedded third-party component, its exact pinned revision, and its license are tracked below.

## Embedded & Planned Component Inventory

| Component / Asset | Target / Path | Upstream Source | Pinned Version / Commit | License | Status |
| --- | --- | --- | --- | --- | --- |
| Hunspell spellchecker engine | `Sources/CHunspell/` | `hunspell/hunspell` | TBD (Phase 1) | MPL-1.1 / LGPL-2.1 / GPL-2.0 | Planned — Phase 1 |
| Turkish Hunspell dictionary & affix rules (`tr_TR.dic`, `tr_TR.aff`) | `Sources/TitizCore/Resources/` | `tdd-ai/hunspell-tr` | TBD (Phase 1) | MPL-2.0 | Planned — Phase 1 |
| Turkish Deasciifier GPA decision-list algorithm & pattern table | `Sources/TitizCore/CharacterEngine/` | Deniz Yüret GPA decision list | TBD (Phase 3) | MIT | Planned — Phase 3 |
| Bundled English common & technical wordlist | `Sources/TitizCore/Resources/` | Open-license wordlist (TBD) | TBD (Phase 3) | Open-license TBD | Planned — Phase 3 |
| Turkish unigram & quantized bigram frequency tables | `Sources/TitizCore/Resources/` | Open / CC-licensed corpus (TBD) | TBD (Phase 3) | Open / CC TBD | Planned — Phase 3 |
| Collision-filtered entity bundles (`Tier2A`, `Tier2B`, `Tier3`) | `Sources/TitizCore/Resources/` | Wikidata (generated offline via `scripts/build-wikidata-entities.py`) | TBD (Phase 4) | CC0 1.0 | Planned — Phase 4 |

---

## Verbatim License Texts & Attributions

Full upstream commit hashes, attributions, and verbatim license texts for every integrated dependency and bundled dataset will be recorded below as each asset is introduced in Phases 1, 3, and 4, and audited in Phase 7.

### 1. Hunspell (`hunspell/hunspell`)
- *Status:* Planned (Phase 1).
- *Notice:* Pending integration.

### 2. Turkish Hunspell Dictionary (`tdd-ai/hunspell-tr`)
- *Status:* Planned (Phase 1).
- *Notice:* Pending integration.

### 3. GPA Decision-List Algorithm (Deniz Yüret)
- *Status:* Planned (Phase 3).
- *Notice:* Pending integration (MIT attribution will be included verbatim).

### 4. English Common & Technical Wordlist
- *Status:* Planned (Phase 3).
- *Notice:* Pending selection and integration.

### 5. Turkish Unigram & Quantized Bigram Frequency Tables
- *Status:* Planned (Phase 3).
- *Notice:* Pending corpus selection and generation.

### 6. Wikidata Entity Bundles (`Tier2A`, `Tier2B`, `Tier3`)
- *Status:* Planned (Phase 4).
- *Notice:* Pending offline generation under CC0 1.0.
