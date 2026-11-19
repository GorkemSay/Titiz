# Titiz — Technical Specification & Development Plan

**Titiz** is an open-source, 100% offline, deterministic macOS menu bar application built for people who write Turkish on an English keyboard.

## Agent Execution Protocol

Any coding agent operating in this repository **must** follow this protocol:

1. **Read `SPEC.md` and `Progress.md` in full** at the start of every session and before beginning any phase.
2. **Execute strictly one phase at a time** (starting from the first incomplete phase in `Progress.md`). Do not rush, do not skip tests, do not improvise shortcuts past the spec, and do not begin the next phase until the current phase passes all exit gates and the user explicitly approves proceeding.
3. **Follow every invariant and constraint below** as hard engineering requirements.

---

## 1. Strict Working Rules (Non-Negotiable)

1. **Language Separation:**
   - **All source code, file/folder names, types, functions, variables, code comments, unit tests, CLI flags, git commit messages, and technical notes in `Progress.md`:** Strictly **English**.
   - **End-user UI strings, TDK rule explanations shown to users, Turkish linguistic test fixtures, and `README.md`:** Clean, natural **Turkish** (with a brief English overview section at the top of `README.md` for international GitHub visitors).
2. **Phase-Gated Execution Discipline:**
   - Execute **only one phase at a time**.
   - At the start of every phase, read `SPEC.md` and `Progress.md`.
   - At the end of every phase:
     1. Run all builds, unit tests, and benchmarks (`swift build`, `swift test`, and `swift run TitizEval` once created).
     2. Update `Progress.md` (check off completed tasks, record measured metrics, log any architectural decisions or discovered risks).
     3. **Pre-authorized automatic commit & push:** Once all checks pass and `Progress.md` is updated, create a clean, atomic git commit and push directly to `origin` **automatically without asking the user for permission each time** (once the GitHub repository is live).
     4. **STOP**, report the exact commands run, test/benchmark outputs, and changed files, and ask the user for explicit approval before starting the next phase.
3. **Zero Silent Failures / Zero Faked Metrics:**
   - Never fake or hardcode benchmark metrics, never disable failing tests, and never ignore compiler warnings that affect correctness or concurrency safety (Swift 6 strict concurrency).
   - If a tool, authentication step (e.g., `gh auth status`), or external resource fails or is ambiguous, stop and ask the user.
4. **Environment Context:**
   - Host machine: Apple Silicon Mac, macOS 27.2.1, Xcode 27.2, Swift 6.4.2.
   - IDE: Antigravity IDE with `Swift (swiftlang)`, `SweetPad`, `LLDB DAP`, and `CodeLLDB` extensions installed.
   - Project system: **Pure Swift Package Manager (`Package.swift`)** — no manual `.xcodeproj` / `.pbxproj` files. Packaging into `Titiz.app` and GitHub Release `.zip`/`.dmg` will be handled by clean scripts in `scripts/`.
   - Deployment target: Declare `macOS(.v14)` in `Package.swift`, using `#available(macOS 26.0, *)` for native Liquid Glass APIs with a graceful material fallback for macOS 14–15. Clearly document in `README.md` that macOS 14–15 runtime compatibility is targeted but unverified until tested on those OS versions.
   - App bundle size: Reliability, precision, and offline accuracy take priority over keeping the bundle tiny. Including rich local dictionaries, entity tables, and quantized statistical frequency tables (~15–30 MB total if needed) is completely acceptable.
   - App logo/icon: Defer final custom logo design to the very end. Use a crisp SF Symbol placeholder (e.g., `character.textbox` or `text.badge.checkmark`) during development.

---

## 2. Product Vision & Core Invariants

### What Titiz Does
A native macOS menu bar utility where a user clicks the menu bar icon, pastes text (`⌘V`), clicks **"Düzelt"**, inspects optional inline edits, and copies the corrected text (`⌘C`). The last **5** corrections are stored locally on the Mac and can be recopied anytime.

### Three Modes
1. **`Türkçe karakterler` (Character Mode):**
   - Restores missing Turkish diacritics (`ç, ğ, ı, İ, ö, ş, ü`) from ASCII input: `yarin disari cikacagim` → `yarın dışarı çıkacağım`.
   - **Out of scope for this mode:** Capitalization changes, punctuation spacing, word splitting, and altering already-correct Turkish diacritics.
2. **`Yazım ve noktalama` (Spelling & Punctuation Mode):**
   - Fixes high-confidence, deterministic TDK spelling/punctuation errors: `Bugün toplantı varmı ?` → `Bugün toplantı var mı?`.
   - **v1 Scope (high-precision only):**
     - Punctuation spacing (extra space before `? ! , . ; :`, missing space after punctuation except URLs/decimals/abbreviations/time).
     - Sentence-start capitalization using `Locale(identifier: "tr_TR")` while respecting protected proper nouns/brands.
     - Question particle `mi/mı/mu/mü` (and conjugated suffixes like `misin`, `mısın`, `miydi`, `muyuz`, `misiniz`, etc.) separation, with strict protection against splitting valid dictionary words ending in `mi`/`mı` (e.g., `ekonomi`, `samimi`, `resmi`, `kimi`, `yirmi`, `acemi`, `ilmi`, `daimi`).
     - Closed-set, indisputable TDK spelling fixes (e.g., `herşey → her şey`, `birşey → bir şey`, `hiçbirşey → hiçbir şey`, `herkez → herkes`, `yanlız → yalnız`, `yalnış → yanlış`, `sağol → sağ ol`, `hoşçakal → hoşça kal`, `ardarda → art arda`).
   - **Explicitly OUT OF SCOPE for v1 auto-apply:** Syntactic/semantic `de/da`, `ki`, and `kar/kâr` automatic rewrites (deferred to v1.1/v2 to protect precision).
3. **`Düzelt` (Combined Mode — Default 1-Click Action):**
   - Runs Character + Spelling together, including **joint split-and-deasciify** for fused ASCII words (`ciktimi → çıktı mı`, `varmi → var mı`, `gordunmu → gördün mü`, `hersey → her şey`).

### Non-Negotiable #1 Priority: Never Break What Is Already Correct ("Doğru Olanı Bozmamak")
- **Precision strictly over recall.** When context is ambiguous, preserve the original text rather than guessing.
- `Intel` must remain `Intel` even at sentence start (never `İntel`).
- Common English / technical / UI terms like `driver`, `feedback`, and UI labels like `Search` must remain untouched.
- Never paraphrase or rewrite style (`Gönder` must stay `Gönder`, never `gönderin`).
- Foreign stem + Turkish suffix (e.g., `loglarini`) remaining untouched is completely acceptable.
- **Target canonical example:**
  - Input: `Intel ekibinden MaviKutu icin cevap geldimi?`
  - Output: `Intel ekibinden MaviKutu için cevap geldi mi?`
  - (`Intel` protected by built-in Tier 2A list, `MaviKutu` protected by Tier 0 CamelCase & Personal Dictionary, `icin → için` in character stage, `geldimi → geldi mi` in spelling stage.)

### Personal Dictionary ("Bu adı hep koru")
- Users can select any single word or multi-word phrase (e.g., `MaviKutu`, `Yeni Proje X`) and click **"Bu adı hep koru"**.
- Takes effect immediately (re-evaluates current text cleanly), persists across sessions in `~/Library/Application Support/Titiz/`, can be inspected/added/deleted in Settings, and **always takes higher priority than built-in entity lists**.

### Distribution & Privacy Constraints
- 100% offline. No accounts, no API keys, no telemetry, no cloud calls, no Node.js/Python runtime required by end users.
- **No Apple Foundation Models (`fm`) in v1.**
- Open-source on GitHub (MIT license for Titiz code, with full third-party license compliance in `THIRD_PARTY_NOTICES.md`).

---

## 3. Target Architecture (`Package.swift`)

Structure the repository into clean, modular SwiftPM targets:

```text
Titiz/
├── SPEC.md                        # This technical specification (preserve intact)
├── Package.swift
├── README.md
├── Progress.md
├── LICENSE
├── THIRD_PARTY_NOTICES.md
├── Sources/
│   ├── CHunspell/                 # Embedded C/C++ Hunspell engine + clean C bridge header
│   ├── TitizCore/                 # Pure Swift, AppKit-free deterministic proofreading engine
│   │   ├── Pipeline/              # Normalization (NFC, tr_TR), Structural Lexer, Combined Orchestrator
│   │   ├── Protection/            # 4-Tier Span Protection, Longest-Match Multi-Word Trie, Personal Dictionary Store
│   │   ├── CharacterEngine/       # 3-Bucket Candidate Classifier, One-Way GPA Scorer, Unigram/Bigram Disambiguator
│   │   ├── SpellingEngine/        # TDK Swift rules + Joint Split-and-Deasciify + rules.json loader
│   │   ├── Models/                # Document, Token, Edit, Confidence, CorrectionResult, HistoryEntry
│   │   └── Resources/             # Pinned tr_TR.dic/aff, rules.json, English wordlist, Wikidata tiers, TR n-gram table
│   ├── TitizEval/                 # CLI evaluation & latency harness (dev + blind set reporting)
│   └── TitizApp/                  # macOS Menu Bar SwiftUI app (Liquid Glass + AppKit focus bridge)
├── Tests/
│   └── TitizCoreTests/            # Comprehensive Swift Testing / XCTest unit & regression suites
├── Datasets/
│   ├── dev_cases.json             # Development & regression test cases
│   └── blind_cases.schema.json    # Schema for held-out blind evaluation set (never tuned against)
└── scripts/
    ├── build-wikidata-entities.py # Offline script to generate collision-filtered Tier2A/2B/3 bundles (CC0)
    ├── build-frequency-tables.py  # Offline script to build compact TR unigram + quantized bigram binary/JSON tables
    └── bundle-app.sh              # Builds release Titiz.app (LSUIElement=true) + GitHub Release .zip/.dmg
```

### Critical Engineering Details (Must Be Implemented Correctly)

1. **Unicode NFC & Turkish Locale Everywhere:**
   - Normalize input to **UTF-8 NFC** on pipeline entry while maintaining exact character/UTF-16 range mapping for UI diff highlights.
   - Use `Locale(identifier: "tr_TR")` for **all** Turkish case conversions (`i ↔ İ`, `ı ↔ I`). Never use default Swift `.lowercased()` / `.uppercased()` on Turkish text (it decomposes `"İ"` into `"i\u{0307}"`).
2. **Embedded Hunspell (`CHunspell`) + Pinned `tdd-ai/hunspell-tr`:**
   - Compile `hunspell/hunspell` (MPL-1.1 / LGPL-2.1 / GPL-2.0) directly inside `CHunspell` with a thread-safe Swift wrapper (`HunspellDictionary`).
   - Bundle pinned `tr_TR.dic` and `tr_TR.aff` from `tdd-ai/hunspell-tr` (MPL-2.0). Record exact commit/tag and license notice in `THIRD_PARTY_NOTICES.md`.
   - Invariant: A word rejected by Hunspell is **never** automatically marked as an error (accounts for Hunspell's 2-fold affix stripping limit and OOV words).
3. **Structural Lexer & 4-Tier Protection:**
   - Lex into typed spans: `word`, `apostropheWord(stem, apostrophe, suffix)` (handling both `'` and `’`), `punctuation`, `whitespace`, `protectedSpan`. Punctuation never glues onto words (`yarin,disari` and `"Search"` lex cleanly).
   - Protection precedence:
     - **Tier 0 (Structural):** URLs, emails, `@handles`, `#tags`, file paths, inline code (`` `...` ``), ALL-CAPS acronyms (`TDK`, `API`, `SQL`), CamelCase/PascalCase/digit-mixed identifiers (`MaviKutu`, `GitHub`, `MenuBarExtra`, `iOS`, `macOS`, `GPT-4`), and quoted short UI labels (`"Search"`, `'Gönder'`).
     - **Tier 1 (Personal Dictionary):** Single and multi-word entries, highest entity precedence, case-sensitive by default (configurable), matches bare stem and apostrophe-inflected forms (`MaviKutu'nun`, `MaviKutu'da`).
     - **Tier 3 (Multi-Word Entities — matched BEFORE single-word Tier 2):** Longest-match token trie (`The Last of Us`, `Red Dead Redemption`, `Visual Studio Code`, etc.).
     - **Tier 2 (Build-Time Collision-Filtered Wikidata CC0 Entities):**
       - Cross-filter every single-word Wikidata candidate against ASCII-folded `tr_TR.dic` AND the English wordlist at build time.
       - **`Tier2A` (Non-Colliding Distinctive Entities):** `Intel`, `Nvidia`, `Spotify`, `Netflix`, `PlayStation`, `Valorant`, `Atatürk`, `İstanbul` → protected in **all** positions including sentence start.
       - **`Tier2B` (Colliding Entities):** `Can`, `It`, `Son`, `Su`, `Yol`, `Güneş`, `Swift`, `Apple`, `Deniz` → protected **only** when strong proper-noun context exists (mid-sentence capitalized, apostrophe+suffix like `Can'a`, or adjacent category/title cue such as `filmi`, `dizisi`, `oyunu`, `şirketi`, `ekibi`, `Bey`, `Hanım`, `Dr.`). Never blocks ordinary Turkish at sentence start.
   - **Foreign-stem suffix invariant:** Do not auto-mutate vowel harmony on suffixes attached to protected foreign stems (`Apple'da`, `iPhone'u`, `GitHub'ta`), because Turkish matches pronunciation rather than spelling.
4. **3-Bucket Character Engine (`TitizCore/CharacterEngine`):**
   - **Strict One-Way Guarantee:** Only evaluate ASCII candidate characters (`c, g, i, o, s, u, C, G, I, O, S, U`). **Never** strip or toggle already-present Turkish diacritics (`ç, ğ, ı, İ, ö, ş, ü`).
   - Extract/implement Deniz Yüret's GPA decision-list algorithm (~150 lines Swift + pattern table, with MIT attribution to Deniz Yüret — do **not** pull `armish/TurkishDeasciifier` as an external repo dependency) as a **feature scorer**, never an unchecked black box.
   - For each unprotected ASCII-eligible word, generate valid Turkish diacritic candidates (pruned by Turkish vowel harmony + Hunspell validation; cap combinatorial search cleanly for long words):
     - **Bucket 0 (0 valid Turkish candidates):** Leave untouched (`driver`, `feedback`, `Search`, `loglarini`, unknown brands).
     - **Bucket 1 (exactly 1 valid Turkish candidate, original invalid, AND original not in bundled ~30k–50k English common+tech wordlist):** Apply confidently (`disari → dışarı`, `cikacagim → çıkacağım`, `icin → için`).
     - **Bucket 2 (2+ valid Turkish candidates including original, OR collides with English wordlist such as `gun`, `is`, `on`, `son`, `can`):** Score candidates using **bundled Turkish unigram + quantized bigram frequency table** combined with GPA agreement. Auto-apply **only** when the confidence margin (log-odds) strictly exceeds a conservative calibrated threshold (resolving high-skew pairs like `is → iş`, `yarin → yarın`, and clear collocations like `erkenden ise gittim → işe`, while protecting `Hava güzel ise çıkarız` and `Fişi prize sok.`). Below threshold → **preserve original** and attach alternative candidates to the result so the user can click to swap if desired.
5. **High-Precision Spelling Engine & Joint Combined Flow:**
   - Rule logic in Swift; metadata (`id`, `name`, `explanationTR`, `tdkReferenceURL`, `examples`) in `Resources/rules.json`.
   - In Combined mode (`Düzelt`), run **joint split-and-deasciify** on Hunspell-invalid fused words ending in question clitics (`ciktimi → çıktı mı`, `varmi → var mı`, `gordunmu → gördün mü`, `olmusmu → olmuş mu`) and closed fused compounds (`hersey → her şey`, `birsey → bir şey`): split stem + clitic, run Bucket 1 deasciification on ASCII stem, validate stem in Hunspell, and harmonize the clitic vowel (`mi/mı/mu/mü`) to the deasciified stem.
   - Attach provenance (`origin: .character | .spelling`, `ruleID`, `confidence`, `original`, `replacement`, `alternatives`) to every edit so Phase 2 never stacks destructive edits on uncertain Phase 1 edits, and the UI supports independent per-edit revert.

---

## 4. UI & Design Direction (Apple Liquid Glass — Strictly Zero "AI Slop")

Design `TitizApp` to feel indistinguishable from a first-party Apple macOS utility:

- **Strictly Forbidden ("No AI Slop"):**
  - No neon purple/blue/cyan gradients, no glowing borders, no floating decorative orbs, no emoji clutter, no fake "AI magic" sparkles or meaningless percentage badges, no nested cards-inside-cards, no cramped web-app dashboard aesthetics.
- **Required Apple-Native Liquid Glass Craft:**
  - On macOS 26+ (`#available(macOS 26.0, *)`), use native SwiftUI Liquid Glass APIs cleanly and sparingly: `.glassEffect(.regular.interactive(), in: ...)` for floating pills/controls, `GlassEffectContainer` for grouped toolbar/mode controls so shapes blend and refract authentically, concentric corner radii, and semantic system colors that work seamlessly in **Light Mode**, **Dark Mode**, and **Reduce Transparency** accessibility mode.
  - On macOS 14–15, fall back cleanly to `.ultraThinMaterial` / `.regularMaterial` with crisp hairline system separators.
  - Typography: Native `SF Pro` system hierarchy, generous line height and whitespace for comfortable reading of Turkish paragraphs, tabular numerals for edit counts and latency (`3 düzeltme · 4 ms`).
  - Layout (~480–520 px wide comfortable popover):
    - **Header:** Clean `Titiz` title, refined segmented mode selector (`Düzelt` | `Karakter` | `Yazım`), History button (last 5), Settings gear.
    - **Editor & Diff Canvas:** Crisp focus-ready text area + inline subtle diff highlights (gentle semantic tint/underline). Clicking any highlighted change opens a clean macOS popover showing `öncesi → sonrası`, TDK rule explanation/link, clickable alternative candidates (if Bucket 2), **"Geri Al"**, and **"Bu adı hep koru"**. Selecting any text also offers **"Bu adı hep koru"** (supports multi-word phrases).
    - **Footer:** Subtle status (`3 düzeltme · 4 ms`), secondary **"Kopyala"** (`⌘⇧C`), primary **"Düzelt"** (`⌘↩`).
    - **History & Settings:** Clean last-5 recopyable list (`Application Support/Titiz/history.json`), Personal Dictionary manager (`personal_dictionary.json`) with search/add/delete, and About/Licenses section.
  - **Mandatory macOS Focus/Paste Reliability:** `MenuBarExtra(.window)` in accessory (`LSUIElement`) apps often loses keyboard focus or drops `⌘V`. Implement and verify a clean AppKit window/focus bridge (or thin `NSStatusItem` + `NSPopover`/`NSPanel` hosting SwiftUI views) so clicking the menu bar icon immediately focuses the text field and `⌘V`, `⌘C`, `⌘A`, `⌘Z` work 100% reliably.

---

## 5. Phased Roadmap & Hard Exit Gates

Follow these phases strictly in order. Stop after completing each phase and request user approval before starting the next.

### Phase 0 — Repository, Docs & Workspace Bootstrap
- Verify `gh auth status` and local git config.
- Initialize git repository and create public GitHub repo **`Titiz`** (`gh repo create Titiz --public --source=. --remote=origin`).
- Preserve the existing **`SPEC.md`** in the project root intact, and create:
  - `.gitignore`
  - `LICENSE` (MIT)
  - `THIRD_PARTY_NOTICES.md` (template ready to record every embedded asset's exact upstream source, commit/version, and license)
  - Detailed **`README.md`** (project goal, "doğru olanı bozmamak" principle, 3 modes, architecture diagram, build instructions, macOS 15+ unsigned Gatekeeper *"Sistem Ayarları → Gizlilik ve Güvenlik → Yine de Aç"* instructions, licensing, roadmap)
  - **`Progress.md`** with this full Phase 0–7 checklist, Architecture Decision Log, Metrics Tracking Table, and Risk Register
  - Minimal compiling `Package.swift` skeleton (`CHunspell`, `TitizCore`, `TitizEval`, `TitizApp`, `TitizCoreTests`).
- **Exit Gate:** `swift build` and `swift test` pass; initial commit (including `SPEC.md`, `README.md`, `Progress.md`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `.gitignore`, and `Package.swift` skeleton) pushed to GitHub; `Progress.md` updated. **Stop and ask for user approval.**

### Phase 1 — Embedded Hunspell (`CHunspell`), NFC/`tr_TR`, Lexer & Tier 0 Protection
- Integrate `hunspell/hunspell` into `CHunspell` and pin `tdd-ai/hunspell-tr` (`tr_TR.dic`, `tr_TR.aff`) as bundle resources; update `THIRD_PARTY_NOTICES.md`.
- Implement thread-safe `HunspellDictionary`, UTF-8 NFC normalizer with offset map, `Locale("tr_TR")` case helpers, Structural Lexer (including `'` / `’` stem-suffix splitting), and Tier 0 structural protection.
- Write thorough unit tests (including `İ/I/ı/i` edge cases, NFD input, `yarin,disari`, `"Search"`, `MaviKutu`, `Intel'den`, URLs, emails, paths).
- **Exit Gate:** All unit tests green; `Progress.md` updated; commit & push; wait for approval.

### Phase 2 — Evaluation Harness (`TitizEval`) & Dataset Discipline
- Build `TitizEval` CLI measuring:
  1. **False-Positive Corruption Rate** (broken originally-correct tokens — target ≤ 0.5%, 0 on clean-sentence subset)
  2. **Protected Entity / Foreign Term Retention** (target ≥ 99%, 100% on Tier 1 & Tier 2A)
  3. **True Error Recall** (Bucket 1 ≥ 92%, overall in-scope ≥ 75–80%)
  4. **Edit Precision** (target ≥ 95%)
  5. **Latency p50 / p95** (300-char & 2,000-char inputs; target p50 < 10 ms, p95 < 25 ms short / < 80 ms long)
- Seed `Datasets/dev_cases.json` with realistic dev/regression examples across all 3 modes (clean sentences, ASCII Turkish, code-switched English+Turkish, colliding entities, minimal pairs, fused clitics).
- Create `Datasets/blind_cases.schema.json` and document a clean workflow for the user to supply/maintain a separate held-out blind set that is **never** inspected during rule tuning.
- **Exit Gate:** `swift run TitizEval` runs cleanly and prints structured baseline report; `Progress.md` updated; commit & push; wait for approval.

### Phase 3 — 3-Bucket Character Engine & Statistical Disambiguator
- Implement internal one-way GPA scorer (MIT attribution in `THIRD_PARTY_NOTICES.md`), vowel-harmony-pruned candidate generator, bundled English common+tech wordlist guard (~30k–50k words), and offline script `scripts/build-frequency-tables.py` producing compact Turkish unigram + quantized bigram frequency tables from an open/CC-licensed corpus (document exact source & license).
- Wire Bucket 0 / Bucket 1 / Bucket 2 decision gate with conservative log-odds threshold and alternative candidate attachment.
- Measure on `TitizEval` (including mixed Turkish+ASCII regression tests proving zero stripping of existing Turkish characters).
- **Exit Gate:** Character mode hits precision & latency gates with zero mixed-text regressions; metrics logged in `Progress.md`; commit & push; wait for approval.

### Phase 4 — 4-Tier Proper Noun Protection & Personal Dictionary
- Build `scripts/build-wikidata-entities.py` (Wikidata CC0, high-notability filtering + build-time collision filtering against ASCII-folded `tr_TR.dic` and English wordlist → versioned `Tier2A`, `Tier2B`, `Tier3` resources).
- Implement longest-match multi-word trie (`The Last of Us`), `Tier2B` context detector (`Can`, `It`, `Son`, `Swift`), foreign-stem apostrophe suffix guard, and `Application Support/Titiz/personal_dictionary.json` store with immediate reload & highest precedence.
- **Exit Gate:** All entity protection & collision unit tests + `TitizEval` entity retention ≥ 99% (100% Tier 1 / Tier 2A); `Progress.md` updated; commit & push; wait for approval.

### Phase 5 — High-Precision Spelling Engine & Joint Combined Mode (`Düzelt`)
- Implement `Resources/rules.json` (TDK citations, explanations, examples) and Swift spelling rules (punctuation spacing, `tr_TR` sentence-start capitalization, `mi/mı/mu/mü` separation, closed TDK list).
- Implement Combined Mode (`Düzelt`) with joint split-and-deasciify (`ciktimi → çıktı mı`, `varmi → var mı`, `gordunmu → gördün mü`, `hersey → her şey`) and edit provenance tracking.
- Verify canonical target (`Intel ekibinden MaviKutu icin cevap geldimi?` → `Intel ekibinden MaviKutu için cevap geldi mi?`) and run full `TitizEval` benchmark across all 3 modes (and blind set if user provides it).
- **Exit Gate:** All Phase 2 precision/recall/latency thresholds met; full report logged in `Progress.md`; commit & push; wait for approval.

### Phase 6 — Native macOS Menu Bar UI (`TitizApp` — Apple Liquid Glass)
- Build `TitizApp` following Section 4 (Apple Liquid Glass on macOS 26+, crisp material fallback on macOS 14–15, zero AI slop).
- Implement reliable AppKit focus/`⌘V`/`⌘C` menu bar window behavior, inline diff highlighting, edit detail popover (TDK reason, alternatives, per-edit revert, "Bu adı hep koru"), selection-based multi-word "Bu adı hep koru", last-5 history persistence, and Settings view.
- Launch and verify live on the local Mac (light mode, dark mode, Reduce Transparency, keyboard shortcuts, persistence across app restarts).
- **Exit Gate:** App runs cleanly, zero focus/paste glitches, all core flows verified; `Progress.md` updated; commit & push; wait for approval.

### Phase 7 — Packaging, Release Script & Final Documentation Polish
- Create `scripts/bundle-app.sh` producing a clean, self-contained `Titiz.app` (`LSUIElement = true`, all embedded dictionaries/tables/rules, optional ad-hoc `codesign --force --deep --sign -`) and `.zip`/`.dmg` release archive.
- Audit `THIRD_PARTY_NOTICES.md` (verify every bundled asset's license and attribution) and polish `README.md` (final architecture, benchmark results, build steps, macOS 15+ Gatekeeper "Yine de Aç" guide, note that final custom app icon is pending).
- **Exit Gate:** Fresh `Titiz.app` built from release script runs cleanly when launched directly; `Progress.md` finalized; commit & push.
