# Third-Party Notices

Titiz's own source code is licensed under the MIT License (see [LICENSE](LICENSE)).

Titiz bundles and incorporates open-source software, linguistic dictionaries, decision-list models, wordlists, and entity/frequency tables so the application can run 100% offline and deterministically on macOS. Every embedded third-party component, its exact pinned revision, and its license are tracked below.

## Embedded & Planned Component Inventory

| Component / Asset | Target / Path | Upstream Source | Pinned Version / Commit | License | Status |
| --- | --- | --- | --- | --- | --- |
| Hunspell spellchecker engine | `Sources/CHunspell/hunspell/` | `https://github.com/hunspell/hunspell` | `v1.7.6` (`15faca15532b34db3106d50f162e5edc2503d6d6`, 2026-10-26) | MPL-1.1 / LGPL-2.1+ / GPL-2.0+ | Integrated — Phase 1 |
| Turkish Hunspell dictionary & affix rules (`tr_TR.dic`, `tr_TR.aff`) | `Sources/TitizCore/Resources/` | `https://github.com/tdd-ai/hunspell-tr` | `main` (`7302eca5f3652fe7ae3d3ec06c44697c97342b4e`, 2023-12-30) | MPL-2.0 | Integrated — Phase 1 |
| Turkish Deasciifier GPA decision-list algorithm & pattern table | `Sources/TitizCore/CharacterEngine/` | Deniz Yüret GPA decision list | TBD (Phase 3) | MIT | Planned — Phase 3 |
| Bundled English common & technical wordlist | `Sources/TitizCore/Resources/` | Open-license wordlist (TBD) | TBD (Phase 3) | Open-license TBD | Planned — Phase 3 |
| Turkish unigram & quantized bigram frequency tables | `Sources/TitizCore/Resources/` | Open / CC-licensed corpus (TBD) | TBD (Phase 3) | Open / CC TBD | Planned — Phase 3 |
| Collision-filtered entity bundles (`Tier2A`, `Tier2B`, `Tier3`) | `Sources/TitizCore/Resources/` | Wikidata (generated offline via `scripts/build-wikidata-entities.py`) | TBD (Phase 4) | CC0 1.0 | Planned — Phase 4 |

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
