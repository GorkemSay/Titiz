# Third-Party Notices

Titiz's own source code is licensed under the MIT License (see [LICENSE](LICENSE)).

Titiz's own source code and rule metadata (`Sources/TitizCore/Resources/rules.json`) are licensed under the MIT License (see [LICENSE](LICENSE)).

Titiz bundles and incorporates open-source software, linguistic dictionaries, decision-list models, wordlists, and entity/frequency tables so the application can run 100% offline and deterministically on macOS. Every embedded third-party component, its exact pinned revision, and its license are tracked below.

## Embedded Component Inventory

| Component / Asset | Target / Path | Upstream Source | Pinned Version / Commit | License | Status |
| --- | --- | --- | --- | --- | --- |
| Hunspell spellchecker engine | `Sources/CHunspell/hunspell/` | `https://github.com/hunspell/hunspell` | `v1.7.6` (`15faca15532b34db3106d50f162e5edc2503d6d6`, 2026-10-26) | MPL-1.1 / LGPL-2.1+ / GPL-2.0+ | Integrated — Phase 1 |
| Turkish Hunspell dictionary & affix rules (`tr_TR.dic`, `tr_TR.aff`) | `Sources/TitizCore/Resources/` | `https://github.com/tdd-ai/hunspell-tr` | `main` (`7302eca5f3652fe7ae3d3ec06c44697c97342b4e`, 2023-12-30) | MPL-2.0 | Integrated — Phase 1 |
| Turkish Deasciifier GPA decision-list algorithm & pattern table (`gpa_patterns.json`) | `Sources/TitizCore/CharacterEngine/` & `Resources/` | `https://github.com/denizyuret/deasciify` | `master` (`9d44765ed722c597e631824bba423bd5de17559a`, 2016-01-14) | MIT | Integrated — Phase 3 |
| Bundled English common & technical wordlist (`en_common_tech.txt`) | `Sources/TitizCore/Resources/` | `jeremy-rifkin/Wordlist` + Leipzig `eng_news_2020_100K` | `df67e6e28bc9c8771816846a962500ec20fa5cfd` (2020-11-10) + `eng_news_2020_100K` | MIT & CC BY 4.0 | Integrated — Phase 3 |
| Turkish unigram & quantized bigram frequency tables (`tr_freq.bin`) | `Sources/TitizCore/Resources/` | Leipzig Corpora Collection (`tur_wikipedia_2021_300K`, `tur_news_2020_300K`) | `2021_300K` & `2020_300K` | CC BY 4.0 | Integrated — Phase 3 |
| Collision-filtered entity bundles (`Tier2A`, `Tier2B`, `Tier3`) | `Sources/TitizCore/Resources/` | Wikidata Query Service (`https://query.wikidata.org/sparql`) + `scripts/build-wikidata-entities.py` | Generated 2026-11-20 (`tier2a_entities.txt`: 1,078; `tier2b_entities.txt`: 748; `tier3_entities.txt`: 1,967) | CC0 1.0 | Integrated — Phase 4 |

---

## Verbatim License Texts & Attributions

Full upstream commit hashes, attributions, and license notices for every integrated dependency and bundled dataset are recorded below.

### 1. Hunspell (`hunspell/hunspell`)
- **Status:** Integrated (Phase 1).
- **Upstream URL:** `https://github.com/hunspell/hunspell`
- **Pinned Revision:** Tag `v1.7.6`, commit `15faca15532b34db3106d50f162e5edc2503d6d6` (2026-10-26).
- **Embedded Files:** Library C/C++ sources and headers from `src/hunspell/` inside `Sources/CHunspell/hunspell/`.
- **License Notice (from upstream `license.hunspell` & `license.myspell`):**

```text
Version: MPL 1.1/GPL 2.0/LGPL 2.1

Copyright (C) 2002-2022 Németh László

The contents of this file are subject to the Mozilla Public License Version
1.1 (the "License"); you may not use this file except in compliance with
the License. You may obtain a copy of the License at
http://www.mozilla.org/MPL/

Software distributed under the License is distributed on an "AS IS" basis,
WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
for the specific language governing rights and limitations under the
License.

Hunspell is based on MySpell which is Copyright (C) 2002 Kevin Hendricks.

Alternatively, the contents of this file may be used under the terms of
either the GNU General Public License Version 2 or later (the "GPL"), or
the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
in which case the provisions of the GPL or the LGPL are applicable instead
of those above. If you wish to allow use of your version of this file only
under the terms of either the GPL or the LGPL, and not to allow others to
use your version of this file under the terms of the MPL, indicate your
decision by deleting the provisions above and replace them with the notice
and other provisions required by the GPL or the LGPL. If you do not delete
the provisions above, a recipient may use your version of this file under
the terms of any one of the MPL, the GPL or the LGPL.
```

Full upstream license texts (`COPYING`, `COPYING.LESSER`, `COPYING.MPL`) are available in the pinned upstream tag `v1.7.6` at `https://github.com/hunspell/hunspell/tree/v1.7.6`.

### 2. Turkish Hunspell Dictionary (`tdd-ai/hunspell-tr`)
- **Status:** Integrated (Phase 1).
- **Upstream URL:** `https://github.com/tdd-ai/hunspell-tr`
- **Pinned Revision:** Branch `main`, commit `7302eca5f3652fe7ae3d3ec06c44697c97342b4e` (2023-12-30).
- **Embedded Files:** `Sources/TitizCore/Resources/tr_TR.dic` and `Sources/TitizCore/Resources/tr_TR.aff`.
- **Contributors:** Ali Safaya, Arda Göktoğan, Deniz Yuret, Emirhan Kurtuluş, Taner Sezer (Turkish Data Depository group).
- **License:** Mozilla Public License Version 2.0 (`MPL-2.0`).

```text
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
```

Citation:
- Ali Safaya, Emirhan Kurtuluş, Arda Göktoğan, and Deniz Yuret. "Mukayese: Turkish NLP Strikes Back." *Findings of the Association for Computational Linguistics: ACL 2022*, pp. 846–863.

### 3. GPA Decision-List Algorithm & Pattern Tables (Deniz Yüret)
- **Status:** Integrated (Phase 3).
- **Upstream URL:** `https://github.com/denizyuret/deasciify`
- **Pinned Revision:** Branch `master`, commit `9d44765ed722c597e631824bba423bd5de17559a` (2016-01-14).
- **Embedded Files:** `Sources/TitizCore/Resources/gpa_patterns.json` (extracted from `turkish.el`) and Swift implementation in `Sources/TitizCore/CharacterEngine/GPAScorer.swift`.
- **License:** MIT License (`LICENSE`).

```text
The MIT License (MIT)

Copyright (c) 2016 denizyuret

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### 4. English Common & Technical Wordlist
- **Status:** Integrated (Phase 3).
- **Upstream Sources:**
  - `https://github.com/jeremy-rifkin/Wordlist` (`master.txt`, commit `df67e6e28bc9c8771816846a962500ec20fa5cfd`, 2020-11-10) — MIT License.
  - Leipzig Corpora Collection `eng_news_2020_100K` (`https://downloads.wortschatz-leipzig.de/corpora/eng_news_2020_100K.tar.gz`) used strictly for ranking common English words — Creative Commons Attribution 4.0 International (CC BY 4.0).
- **Embedded File:** `Sources/TitizCore/Resources/en_common_tech.txt` (40,171 lowercase ASCII English + modern software/UI words).
- **MIT Notice (`jeremy-rifkin/Wordlist`):**

```text
Copyright 2015-2019 Jeremy M. Rifkin

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### 5. Turkish Unigram & Quantized Bigram Frequency Tables
- **Status:** Integrated (Phase 3).
- **Upstream Sources:** Leipzig Corpora Collection (Wortschatz Leipzig, Leipzig University):
  - `tur_wikipedia_2021_300K` (`https://downloads.wortschatz-leipzig.de/corpora/tur_wikipedia_2021_300K.tar.gz`)
  - `tur_news_2020_300K` (`https://downloads.wortschatz-leipzig.de/corpora/tur_news_2020_300K.tar.gz`)
- **Embedded Files:** `Sources/TitizCore/Resources/tr_freq.bin` and `Sources/TitizCore/Resources/tr_freq_meta.json` (generated via `scripts/build-frequency-tables.py`).
- **License:** Creative Commons Attribution 4.0 International (`CC BY 4.0`, `https://creativecommons.org/licenses/by/4.0/`).
- **Citation:** Dirk Goldhahn, Thomas Eckart, and Uwe Quasthoff. "Building Large Monolingual Dictionaries at the Leipzig Corpora Collection: From 100 to 200 Languages." *Proceedings of the Eighth International Conference on Language Resources and Evaluation (LREC'12)*, pp. 759–765, 2012.

### 6. Wikidata Entity Bundles (`Tier2A`, `Tier2B`, `Tier3`)
- **Status:** Integrated (Phase 4).
- **Upstream Source:** Wikidata Query Service (`https://query.wikidata.org/sparql`), Wikimedia Foundation (snapshot fetched 2026-11-20, 4,765 structured entity records across countries, cities/Turkish provinces, tech brands/software, games/media, Turkish institutions, and notable figures) + collision filtering and curated supplement via `scripts/build-wikidata-entities.py`.
- **Embedded Files:** `Sources/TitizCore/Resources/tier2a_entities.txt` (1,078 non-colliding entities), `Sources/TitizCore/Resources/tier2b_entities.txt` (748 colliding entities), `Sources/TitizCore/Resources/tier3_entities.txt` (1,967 multi-word entities), and `Sources/TitizCore/Resources/wikidata_meta.json`.
- **License:** Creative Commons Zero v1.0 Universal (`CC0-1.0`, `https://creativecommons.org/publicdomain/zero/1.0/`).

```text
CC0 1.0 Universal (Public Domain Dedication)

All structured data in Wikidata is available under the Creative Commons CC0 License.
The person who associated a work with this deed has dedicated the work to the public
domain by waiving all of his or her rights to the work worldwide under copyright law,
including all related and neighboring rights, to the extent allowed by law.
```
