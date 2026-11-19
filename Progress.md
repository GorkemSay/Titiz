# Titiz Development Progress

## Project & Environment Metadata

- **Repository:** `https://github.com/GorkemSay/Titiz` (public)
- **Local Workspace:** `/Users/gorkemsay/Desktop/App Devoloping/Titiz`
- **Host Machine:** Apple Silicon Mac, macOS 27.2.1
- **Toolchain:** Xcode 27.2 (Build 27B52), Apple Swift 6.4.2 (`arm64-apple-macosx27.2.0`)
- **Deployment Target:** `macOS(.v14)` in `Package.swift` (with `#available(macOS 26.0, *)` Liquid Glass guard)
- **Git Identity:** `Görkem Say <gorkemsay@protonmail.com>` (GitHub account: `GorkemSay`)

---

## Phased Roadmap Checklist

### Phase 0 — Repository, Docs & Workspace Bootstrap
- [x] Verify `gh auth status` and local git configuration (`init.defaultBranch` unset -> initialized explicitly with `git init -b main`)
- [x] Initialize local git repository (`main`) while preserving `SPEC.md` completely intact
- [x] Create `.gitignore`, `LICENSE` (MIT), `THIRD_PARTY_NOTICES.md`, `README.md`, and `Progress.md`
- [x] Create compiling pure-SwiftPM `Package.swift` skeleton (`CHunspell`, `TitizCore`, `TitizEval`, `TitizApp`, `TitizCoreTests`)
- [x] Run `swift build`, `swift test`, and `swift run TitizEval` cleanly with zero compiler warnings
- [x] Create public GitHub repository `GorkemSay/Titiz` and push initial Phase 0 commit to `origin/main`

### Phase 1 — Embedded Hunspell (`CHunspell`), NFC/`tr_TR`, Lexer & Tier 0 Protection
- [x] Integrate `hunspell/hunspell` into `CHunspell`
- [x] Pin `tdd-ai/hunspell-tr` (`tr_TR.dic`, `tr_TR.aff`) as bundle resources and record revision/license in `THIRD_PARTY_NOTICES.md`
- [x] Implement thread-safe `HunspellDictionary` wrapper
- [x] Implement UTF-8 NFC normalizer with character/UTF-16 offset mapping and `Locale(identifier: "tr_TR")` case helpers
- [x] Implement Structural Lexer (including `'` / `’` stem-suffix splitting) and Tier 0 structural protection
- [x] Write thorough unit tests (`İ/I/ı/i` edge cases, NFD input, `yarin,disari`, `"Search"`, `MaviKutu`, `Intel'den`, URLs, emails, paths)
- [x] Pass Phase 1 exit gate, update `Progress.md`, commit & push

### Phase 2 — Evaluation Harness (`TitizEval`) & Dataset Discipline
- [x] Build `TitizEval` CLI measuring False-Positive Corruption Rate, Protected Entity/Foreign Term Retention, True Error Recall, Edit Precision, and Latency p50/p95 (300-char & 2,000-char inputs)
- [x] Seed `Datasets/dev_cases.json` across all 3 modes
- [x] Create `Datasets/blind_cases.schema.json` and document held-out blind evaluation workflow
- [x] Pass Phase 2 exit gate (`swift run TitizEval` structured baseline report), update `Progress.md`, commit & push

### Phase 3 — 3-Bucket Character Engine & Statistical Disambiguator
- [x] Implement internal one-way GPA decision-list scorer (MIT attribution to Deniz Yüret in `THIRD_PARTY_NOTICES.md`)
- [x] Implement vowel-harmony-pruned candidate generator and bundled ~30k–50k English common+tech wordlist guard
- [x] Create `scripts/build-frequency-tables.py` producing compact Turkish unigram + quantized bigram frequency tables from an open/CC-licensed corpus (source & license documented)
- [x] Wire Bucket 0 / Bucket 1 / Bucket 2 decision gate with conservative log-odds threshold and alternative candidate attachment
- [x] Verify mixed Turkish+ASCII regression tests (zero stripping of existing Turkish diacritics) and hit Phase 3 precision & latency gates
- [x] Update `Progress.md` with measured metrics, commit & push

### Phase 4 — 4-Tier Proper Noun Protection & Personal Dictionary
- [ ] Build `scripts/build-wikidata-entities.py` (Wikidata CC0, high-notability filtering + build-time collision filtering against ASCII-folded `tr_TR.dic` and English wordlist -> `Tier2A`, `Tier2B`, `Tier3` resources)
- [ ] Implement longest-match multi-word trie (`The Last of Us`), `Tier2B` context detector, and foreign-stem apostrophe suffix guard
- [ ] Implement `Application Support/Titiz/personal_dictionary.json` store with immediate reload and highest precedence
- [ ] Pass entity protection & collision unit tests + `TitizEval` entity retention >= 99% (100% Tier 1 / Tier 2A), update `Progress.md`, commit & push

### Phase 5 — High-Precision Spelling Engine & Joint Combined Mode (`Düzelt`)
- [ ] Implement `Resources/rules.json` (TDK citations, explanations, examples) and Swift spelling rules (punctuation spacing, `tr_TR` sentence-start capitalization, `mi/mı/mu/mü` separation, closed TDK list)
- [ ] Implement Combined Mode (`Düzelt`) with joint split-and-deasciify (`ciktimi -> çıktı mı`, `varmi -> var mı`, `gordunmu -> gördün mü`, `hersey -> her şey`) and edit provenance tracking
- [ ] Verify canonical target (`Intel ekibinden MaviKutu icin cevap geldimi?` -> `Intel ekibinden MaviKutu için cevap geldi mi?`)
- [ ] Run full `TitizEval` benchmark across all 3 modes (plus blind set if provided), verify all Phase 2 thresholds met, log full report in `Progress.md`, commit & push

### Phase 6 — Native macOS Menu Bar UI (`TitizApp` — Apple Liquid Glass)
- [ ] Build `TitizApp` following Apple Liquid Glass guidelines on macOS 26+ (`#available(macOS 26.0, *)`) and clean material fallback on macOS 14–15 (zero AI slop)
- [ ] Implement reliable AppKit focus/`⌘V`/`⌘C` menu bar window bridge
- [ ] Implement inline diff highlighting, edit detail popover (TDK reason, alternatives, per-edit revert, "Bu adı hep koru"), selection-based multi-word "Bu adı hep koru", last-5 history persistence, and Settings view
- [ ] Launch and verify live on local Mac (light mode, dark mode, Reduce Transparency, keyboard shortcuts, persistence across restarts), update `Progress.md`, commit & push

### Phase 7 — Packaging, Release Script & Final Documentation Polish
- [ ] Create `scripts/bundle-app.sh` producing self-contained `Titiz.app` (`LSUIElement = true`, all embedded dictionaries/tables/rules, optional ad-hoc `codesign --force --deep --sign -`) and `.zip`/`.dmg` release archive
- [ ] Audit `THIRD_PARTY_NOTICES.md` and polish `README.md` (final architecture, benchmark results, build steps, Gatekeeper instructions, pending custom app icon note)
- [ ] Verify fresh `Titiz.app` built from release script runs cleanly when launched directly, finalize `Progress.md`, commit & push

---

## Architecture Decision Log

| ID | Date | Decision | Rationale |
| --- | --- | --- | --- |
| ADR-001 | 2026-11-19 | Use pure SwiftPM (`swift-tools-version: 6.0`, Swift 6 strict concurrency) with 5 targets (`CHunspell`, `TitizCore`, `TitizEval`, `TitizApp`, `TitizCoreTests`) and no `.xcodeproj`. | Keeps builds reproducible from CLI and IDE (`SweetPad`/`swiftlang`) and strictly isolates AppKit UI from the pure-Swift proofreading engine. |
| ADR-002 | 2026-11-19 | Declare `macOS(.v14)` in `Package.swift` and guard native Liquid Glass APIs with `#available(macOS 26.0, *)` + material fallback. | Enables native Liquid Glass on macOS 26+ while maintaining a clean compile target for macOS 14–15 (runtime behavior on 14–15 remains unverified until tested on those versions). |
| ADR-003 | 2026-11-19 | Adopt Swift Testing (`import Testing`) as the primary test framework for `TitizCoreTests`. | Ships natively with Xcode 27.2 / Swift 6.4.2 and provides expressive parameterized suites and clear failure diagnostics. |
| ADR-004 | 2026-11-19 | Expose `CHunspell` via an `extern "C"` bridge header (`Sources/CHunspell/include/CHunspell.h`) while keeping C++ Hunspell internals isolated behind it. | Avoids C++ Swift interop complexity in `TitizCore` and establishes a clean ABI boundary for Phase 1 Hunspell integration. |
| ADR-005 | 2026-11-19 | Ignore `Datasets/blind_cases.json` and `Datasets/*.local.json` in `.gitignore` while tracking `Datasets/blind_cases.schema.json`. | Ensures user-provided held-out blind evaluation data stays local and is never accidentally committed or tuned against. |
| ADR-006 | 2026-11-19 | Embed `hunspell/hunspell` `v1.7.6` (`15faca15532b34db3106d50f162e5edc2503d6d6`) statically (`HUNSPELL_STATIC`, `BUILDING_LIBHUNSPELL`) behind an `OpaquePointer` C ABI (`CHunspell.h`) with pre-init `access(..., R_OK)` validation and `NSLock` synchronization in `HunspellDictionary`. | Isolates C++ Hunspell headers from Swift 6, avoids silent empty-dictionary creation on missing files, and ensures thread-safe concurrent access. |
| ADR-007 | 2026-11-19 | Normalize input to UTF-8 NFC via extended grapheme cluster mapping in `TextNormalizer`, using UTF-8 byte equality (`elementsEqual`) rather than canonically-equivalent Swift `==`. | Reliably detects NFD inputs while preserving exact UTF-16 and `String.Index` offset mappings for UI diff highlights. |
| ADR-008 | 2026-11-19 | Keep quote punctuation as separate `.punctuation` tokens in `StructuralLexer` and apply `.quotedUILabel` Tier 0 protection in `Tier0Protector` over the token stream. | Preserves clean punctuation boundaries for Phase 5 spacing rules while protecting short quoted UI labels (`"Search"`, `'Gönder'`, `“Yine de Aç”`). |
| ADR-009 | 2026-11-19 | Align `EvalScorer` diffs via weighted non-whitespace LCS (exact match > Turkish ASCII-folded match) with gap prefix/suffix trimming and minimal `ExpectedEdit` signature matching. | Prevents space tokens inside word splits (`varmı ? -> var mı?`, `güzelmiydi -> güzel miydi`) from misaligning across sentence spaces while keeping multi-word edits distinct. |
| ADR-010 | 2026-11-19 | Enforce strict summary-only blind output in `ReportFormatter` (`--blind`) paired with gitignored local `Datasets/blind_cases.json` and `Datasets/blind_cases.schema.json`. | Guarantees held-out blind examples are never leaked or tuned against during rule/threshold calibration. |
| ADR-011 | 2026-11-19 | Implement internal one-way Deniz Yüret GPA decision-list scorer (`gpa_patterns.json` from `denizyuret/deasciify` `9d44765ed722c597e631824bba423bd5de17559a`, MIT) using zero-allocation ASCII byte FNV-1a matching and `weightedSum / Double(predictions.count)` agreement normalization. | Guarantees strict one-way diacritic preservation, eliminates rank-3000 fallback rule inflation, and keeps release latency well under 10 ms. |
| ADR-012 | 2026-11-19 | Add `chunspell_spell_batch` in `CHunspell` + `HunspellDictionary.containsBatch(_:assumeNFC:)` (32-item chunks, single lock acquisition) with intra-document caching (`mutableCount <= 7`). | Eliminates per-candidate lock and ICU NFC overhead across up to 128 dictionary probes, cutting 1,926-char Release p50 latency from 11.355 ms to 3.450 ms. |
| ADR-013 | 2026-11-19 | Bundle 40,171-word English common+tech wordlist (`en_common_tech.txt` from MIT `jeremy-rifkin/Wordlist` + CC BY 4.0 Leipzig `eng_news_2020_100K` + curated tech terms) and `containsForeignStemWithTurkishSuffix(_:)` demoting English-stem + Turkish-suffix tokens (`loglarini`) from Bucket 1 to Bucket 2. | Prevents obscure `tr_TR.dic` entries (e.g., `loğ`) from corrupting code-switched Turkish technical terms. |
| ADR-014 | 2026-11-19 | Build compact binary frequency table `tr_freq.bin` (150,000 unigrams + 337,054 ambiguity-filtered bigrams, 4.18 MiB) offline via `scripts/build-frequency-tables.py` from CC BY 4.0 Leipzig Turkish corpora (`tur_wikipedia_2021_300K` + `tur_news_2020_300K`, 8,065,855 tokens) with Lidstone smoothing and binary-search `TurkishFrequencyTable`. | Keeps Titiz 100% offline with compact storage and fast PMI-boosted Bucket 2 disambiguation. |

---

## Metrics Tracking Table

Target gates (from `SPEC.md` Phase 2):
- **False-Positive Corruption Rate:** <= 0.5% overall, 0% on clean-sentence subset
- **Protected Entity / Foreign Term Retention:** >= 99% overall, 100% on Tier 1 & Tier 2A
- **True Error Recall:** Bucket 1 >= 92%, overall in-scope >= 75–80%
- **Edit Precision:** >= 95%
- **Latency p50 / p95:** p50 < 10 ms; p95 < 25 ms (300-char) / < 80 ms (2,000-char)

| Phase | Dataset / Scope | False-Positive Corruption | Entity / Foreign Retention | True Error Recall | Edit Precision | Latency p50 / p95 (300c / 2000c) |
| --- | --- | --- | --- | --- | --- | --- |
| Phase 0 | Bootstrap skeleton (`TitizEval` harness arrives in Phase 2) | N/A | N/A | N/A | N/A | N/A |
| Phase 1 | Embedded Hunspell, NFC/`tr_TR`, Lexer, Tier 0 (`TitizEval` harness arrives in Phase 2) | N/A | N/A | N/A | N/A | N/A |
| Phase 2 | `Datasets/dev_cases.json` (60 cases, pass-through baseline) | 0.00% (0/340); Clean: 0.00% (0/123) | 100.00% (48/48; T1: 3/3, T2A: 9/9) | Bucket 1: 0.00% (0/70); Overall: 0.00% (0/132) | N/A (0 edits) | 273c: 0.412 / 0.553 ms; 1926c: 1.955 / 2.441 ms |
| Phase 3 (Character) | `Datasets/dev_cases.json` (20 `character` cases, Release) | 0.00% (0/78); Clean: 0.00% (0/45) | 100.00% (9/9; T2A: 1/1) | Bucket 1: 100.00% (37/37); Overall: 100.00% (44/44) | 100.00% (44/44) | Release: 273c 0.364 / 0.399 ms; 1926c 3.456 / 3.550 ms (Debug: 1.959 / 2.080 ms; 14.967 / 15.465 ms) |
| Phase 3 (All 60 Dev) | `Datasets/dev_cases.json` (60 cases; Phase 4–5 rules pending) | 0.00% (0/340); Clean: 0.00% (0/123) | 100.00% (48/48; T1: 3/3, T2A: 9/9) | Bucket 1: 100.00% (70/70); Overall: 64.39% (85/132) | 96.59% (85/88) | Release: 273c 0.361 / 0.452 ms; 1926c 3.450 / 3.679 ms |

---

## Risk Register

| ID | Risk | Impact | Mitigation |
| --- | --- | --- | --- |
| R-01 | `CHunspell` C++ compilation flags or macro differences on macOS / SwiftPM (`cxx17`). | Delays Phase 1 dictionary integration. | Isolate C++ behind `CHunspell.h` (`extern "C"`), pass explicit `cxxSettings` in `Package.swift`, and add bridge tests early in Phase 1. |
| R-02 | `MenuBarExtra(.window)` in `LSUIElement` macOS apps dropping keyboard focus or `⌘V` / `⌘C` pasteboard shortcuts. | Breaks primary copy-paste UX in Phase 6. | Implement an explicit AppKit focus/window bridge (`NSStatusItem` + `NSPopover`/`NSPanel` or verified focus coordinator) and test live on macOS. |
| R-03 | macOS 14–15 runtime compatibility is unverified on the macOS 27.2.1 host. | UI layout or material fallback regressions on older macOS releases. | Keep `#available(macOS 26.0, *)` guards clean and explicitly document unverified status in `README.md` until tested on macOS 14–15. |
| R-04 | Short-word and English-Turkish collisions (e.g., `is`, `son`, `on`, `can`, `gun`) causing false positives. | Violates #1 "never break what is already correct" rule. | Enforce Bucket 2 conservative log-odds threshold, bundled English wordlist collision check, and build-time Wikidata Tier2A/2B cross-filtering. |
| R-05 | Hunspell's 2-fold affix stripping limit rejecting valid agglutinative Turkish inflections. | Could trigger spurious edits if Hunspell rejection were treated as proof of error. | Enforce strict invariant: Hunspell rejection alone never triggers an error; only evaluate constrained ASCII diacritic candidates and known high-precision TDK rules. |
| R-06 | `tdd-ai/hunspell-tr` `tr_TR.aff` (177,803 lines) takes ~2–3s to parse per instance in debug builds and derives ambiguous ASCII forms such as `yarin` (`ya` + `SFX 27513`). | Per-request dictionary initialization would violate latency gates; naive Bucket 1 assumptions on `yarin` would under-correct. | Share a single cached `HunspellDictionary` instance across `TitizEngine` requests, and handle `yarin -> yarın` via Phase 3 Bucket 2 statistical disambiguation. |

---

## Phase 0 Verification Notes

- `swift build` — Passed (`exit 0`, 0 errors, 0 compiler warnings; built all 5 targets: `CHunspell`, `TitizCore`, `TitizEval`, `TitizApp`, `TitizCoreTests`).
- `swift test` — Passed (`exit 0`, Swift Testing: 3 tests in 1 suite `"Titiz Bootstrap"` passed in 0.001 seconds; 0 failures).
- `swift run TitizEval` — Passed (`exit 0`, printed `TitizCore version: 0.1.0-dev` and `CHunspell bridge version: 0.0.0-bootstrap`).
- `SPEC.md` — Verified present and unmodified.

## Phase 1 Verification Notes

- **Pinned Upstream Assets:**
  - `hunspell/hunspell` `v1.7.6` (`15faca15532b34db3106d50f162e5edc2503d6d6`, 2026-10-26) in `Sources/CHunspell/hunspell/`.
  - `tdd-ai/hunspell-tr` `main` (`7302eca5f3652fe7ae3d3ec06c44697c97342b4e`, 2023-12-30) in `Sources/TitizCore/Resources/tr_TR.{dic,aff}`.
- `swift build` — Passed (`exit 0`, 0 errors, 0 Swift compiler warnings).
- `swift test` — Passed (`exit 0`, Swift Testing: 20 tests across 4 suites — `"Titiz Bootstrap"`, `"HunspellDictionary"`, `"TurkishLocale & TextNormalizer"`, `"StructuralLexer & Tier 0 Protection"` — passed in 3.511 seconds; 0 failures).
- `swift run TitizEval` — Passed (`exit 0`, printed `TitizCore version: 0.1.0-dev` and `CHunspell bridge version: 1.7.6`).
- `SPEC.md` — Verified present and unmodified.

## Phase 2 Verification Notes

- **Dataset Seeded:** `Datasets/dev_cases.json` (60 cases: 20 `character`, 20 `spelling`, 20 `combined`; 7 clean sentences, 70 Bucket 1 edits, 132 total in-scope edits, 48 protected spans across `tier0`, `tier1`, `tier2A`, `tier2B`, `tier3`, `foreign_term`).
- **Blind Discipline Artifacts:** `Datasets/blind_cases.schema.json` (JSON Schema Draft 2020-12) and `Datasets/README.md`.
- `swift build` — Passed (`exit 0`, 0 errors, 0 Swift compiler warnings).
- `swift test` — Passed (`exit 0`, Swift Testing: 27 tests across 5 suites including `"TitizEval Harness & Datasets"` passed in 3.667 seconds; 0 failures).
- `swift run TitizEval` — Passed (`exit 0`, baseline report over 60 cases: FP 0.00% [0/340], Clean FP 0.00% [0/123], Retention 100.00% [48/48], Recall Bucket 1 0.00% [0/70], Recall Overall 0.00% [0/132], Precision N/A [0 edits]; Latency 273c p50=0.412 ms / p95=0.553 ms, 1926c p50=1.955 ms / p95=2.441 ms).
- `swift run TitizEval --json --skip-latency` — Passed (`exit 0`, valid JSON report emitted).
- `SPEC.md` — Verified present and unmodified.

## Phase 3 Verification Notes

- **Pinned Upstream & Corpus Assets (`THIRD_PARTY_NOTICES.md` updated):**
  - `denizyuret/deasciify` (`9d44765ed722c597e631824bba423bd5de17559a`, MIT) -> `Sources/TitizCore/Resources/gpa_patterns.json` via `scripts/build-character-assets.py`.
  - `jeremy-rifkin/Wordlist` (`df67e6e28bc9c8771816846a962500ec20fa5cfd`, MIT) + Leipzig Corpora `eng_news_2020_100K` (CC BY 4.0) + curated tech terms -> `Sources/TitizCore/Resources/en_common_tech.txt` (40,171 words).
  - Leipzig Corpora `tur_wikipedia_2021_300K` + `tur_news_2020_300K` (CC BY 4.0, 8,065,855 tokens) -> `Sources/TitizCore/Resources/tr_freq.bin` (150,000 unigrams, 337,054 ambiguity-filtered bigrams, 4.18 MiB) & `tr_freq_meta.json` via `scripts/build-frequency-tables.py`.
- `swift build` — Passed (`exit 0`, 0 errors, 0 Swift compiler warnings).
- `swift test` — Passed (`exit 0`, Swift Testing: 36 tests across 6 suites including `"CharacterEngine & Disambiguator"` passed in 3.768 seconds; 0 failures).
- `swift run TitizEval --mode character --verbose` (Debug, 20 `character` cases) — Passed (`exit 0`, 20/20 exact match, FP 0.00% [0/78], Clean FP 0.00% [0/45], Retention 100.00% [9/9], Bucket 1 Recall 100.00% [37/37], Overall Recall 100.00% [44/44], Precision 100.00% [44/44]; Debug `.combined` latency: 273c p50=1.959 ms / p95=2.080 ms, 1926c p50=14.967 ms / p95=15.465 ms).
- `swift run -c release TitizEval --mode character` (Release, 20 `character` cases) — Passed (`exit 0`, identical 100.00% quality metrics; Release `.combined` latency: 273c p50=0.364 ms / p95=0.399 ms [PASS], 1926c p50=3.456 ms / p95=3.550 ms [PASS]).
- `swift run -c release TitizEval` (Release, all 60 cases) — Exited `0`, FP 0.00% [0/340], Clean FP 0.00% [0/123], Retention 100.00% [48/48; T1: 3/3, T2A: 9/9], Bucket 1 Recall 100.00% [70/70], Overall In-Scope Recall 64.39% [85/132] (Phases 4–5 spelling/combined rules pending), Precision 96.59% [85/88]; Release `.combined` latency: 273c p50=0.361 ms / p95=0.452 ms [PASS], 1926c p50=3.450 ms / p95=3.679 ms [PASS].
- `SPEC.md` — Verified present and unmodified.
