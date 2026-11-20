#!/usr/bin/env python3
"""Fetches high-notability Wikidata (CC0 1.0) entities and performs build-time
collision filtering against ASCII-folded `tr_TR.dic` and `en_common_tech.txt`
to produce `Tier2A`, `Tier2B`, and `Tier3` resource bundles.

Usage:
    # Step 1: Fetch Wikidata CC0 snapshot to a temporary cache directory:
    python3 scripts/build-wikidata-entities.py --fetch --cache /tmp/titiz-phase4-fetch/wikidata_raw.json

    # Step 2: Cross-filter and emit TitizCore resource files:
    python3 scripts/build-wikidata-entities.py --cache /tmp/titiz-phase4-fetch/wikidata_raw.json
"""

from __future__ import annotations

import argparse
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parent.parent
RESOURCES_DIR = ROOT / "Sources" / "TitizCore" / "Resources"
TR_DIC_PATH = RESOURCES_DIR / "tr_TR.dic"
EN_WORDLIST_PATH = RESOURCES_DIR / "en_common_tech.txt"

SPARQL_ENDPOINT = "https://query.wikidata.org/sparql"
USER_AGENT = "TitizEntityBuilder/1.0 (https://github.com/GorkemSay/Titiz; offline-turkish-proofreader)"

# Curated high-value canonical entities explicitly anchored from SPEC.md and Turkish digital domain
# (supplemented alongside Wikidata SPARQL slices; all subject to the exact same build-time collision filter).
CANONICAL_SUPPLEMENT: list[tuple[str, str]] = [
    ("Intel", "org_tech"),
    ("Nvidia", "org_tech"),
    ("Spotify", "software_platform"),
    ("Netflix", "software_platform"),
    ("PlayStation", "gaming"),
    ("Valorant", "gaming"),
    ("Atatürk", "tr_proper"),
    ("İstanbul", "tr_place"),
    ("Ankara", "tr_place"),
    ("İzmir", "tr_place"),
    ("Türkiye", "tr_place"),
    ("Can", "colliding_name"),
    ("Deniz", "colliding_name"),
    ("Güneş", "colliding_name"),
    ("It", "colliding_work"),
    ("Son", "colliding_work"),
    ("Su", "colliding_name"),
    ("Yol", "colliding_work"),
    ("Swift", "software_lang"),
    ("Apple", "org_tech"),
    ("GitHub", "software_platform"),
    ("AppKit", "software_framework"),
    ("SwiftUI", "software_framework"),
    ("Xcode", "software_tool"),
    ("iPhone", "product"),
    ("macOS", "software_os"),
    ("iOS", "software_os"),
    ("iPad", "product"),
    ("MacBook", "product"),
    ("Google", "org_tech"),
    ("Microsoft", "org_tech"),
    ("OpenAI", "org_tech"),
    ("Anthropic", "org_tech"),
    ("WhatsApp", "software_platform"),
    ("YouTube", "software_platform"),
    ("Instagram", "software_platform"),
    ("LinkedIn", "software_platform"),
    ("Kubernetes", "software_tool"),
    ("The Last of Us", "work_game"),
    ("Red Dead Redemption", "work_game"),
    ("Visual Studio Code", "software_tool"),
    ("Türk Dil Kurumu", "tr_institution"),
    ("Boğaziçi Üniversitesi", "tr_institution"),
    ("Orta Doğu Teknik Üniversitesi", "tr_institution"),
    ("Atatürk Havalimanı", "tr_place"),
    ("İstanbul Havalimanı", "tr_place"),
    # Common Turkish given names (subject to collision filter -> colliding ones route to Tier2B)
    ("Ahmet", "tr_name"), ("Mehmet", "tr_name"), ("Mustafa", "tr_name"), ("Ali", "tr_name"),
    ("Ömer", "tr_name"), ("Emre", "tr_name"), ("Burak", "tr_name"), ("Mert", "tr_name"),
    ("Kaan", "tr_name"), ("Cem", "tr_name"), ("Ayşe", "tr_name"), ("Fatma", "tr_name"),
    ("Zeynep", "tr_name"), ("Elif", "tr_name"), ("Selin", "tr_name"), ("Ece", "tr_name"),
    ("Aslı", "tr_name"), ("Defne", "tr_name"), ("İpek", "tr_name"), ("Barış", "tr_name"),
    ("Umut", "tr_name"), ("Kemal", "tr_name"), ("Hakan", "tr_name"), ("Serkan", "tr_name"),
    ("Tolga", "tr_name"), ("Murat", "tr_name"), ("Onur", "tr_name"), ("Engin", "tr_name"),
    ("Ufuk", "tr_name"), ("Erdem", "tr_name"), ("Bilge", "tr_name"), ("Yağmur", "tr_name"),
    ("Pınar", "tr_name"), ("Nehir", "tr_name"), ("Özlem", "tr_name"), ("Derya", "tr_name"),
]

# Entries present as lowercase stems in tdd-ai/hunspell-tr (`tr_TR.dic`) that function
# strictly as capitalized proper nouns in Turkish (never common lower-case nouns).
HUNSPELL_PROPER_NOUN_ONLY_EXCEPTIONS = {
    "atatürk",
    "ataturk",
    "istanbul",
    "i̇stanbul",
    "ankara",
    "izmir",
    "i̇zmir",
    "türkiye",
    "turkiye",
    "boğaziçi",
    "bogazici",
    "anıtkabir",
    "anitkabir",
}

# Distinctive brands, platforms, and major geopolitical proper nouns that appear in
# Leipzig English news frequency lists only as proper nouns (not ordinary lowercase English common nouns).
# Never overrides Turkish `tr_TR.dic` common words or COMMON_WORD_SAFETY_BLOCKLIST.
ENGLISH_NEWS_PROPER_NOUN_ALLOWLIST = {
    "Intel", "Nvidia", "Spotify", "Netflix", "PlayStation", "Valorant",
    "Atatürk", "İstanbul", "Ankara", "İzmir", "Türkiye", "Bursa", "Antalya", "Adana", "Konya", "Trabzon",
    "Google", "Microsoft", "YouTube", "Instagram", "WhatsApp", "LinkedIn", "TikTok",
    "GitHub", "OpenAI", "Anthropic", "Samsung", "Nintendo", "Wikipedia",
    "London", "Paris", "Berlin", "Tokyo", "Madrid", "Barcelona", "Munich",
    "Vienna", "Prague", "Athens", "Cairo", "Seoul", "Moscow", "Toronto",
    "Chicago", "Seattle", "Boston", "Miami",
}

# Short/frequent Turkish & English tokens that must NEVER enter Tier2A even if omitted from stems.
COMMON_WORD_SAFETY_BLOCKLIST = {
    "ab", "ac", "ad", "ag", "ah", "ak", "al", "am", "an", "ar", "as", "at", "av", "ay", "az",
    "ba", "be", "bi", "bu", "ca", "ce", "da", "de", "di", "do", "du", "eb", "ed", "ef", "ek",
    "el", "em", "en", "er", "es", "et", "ev", "ey", "fa", "fe", "fi", "ga", "ge", "gi", "go",
    "ha", "he", "hi", "ho", "ic", "id", "il", "im", "in", "ip", "is", "it", "iz", "ka", "ke",
    "ki", "ko", "ku", "la", "le", "ma", "me", "mi", "mu", "ne", "no", "nu", "od", "of", "oh",
    "ok", "ol", "om", "on", "or", "ot", "ov", "oy", "oz", "pa", "pe", "pi", "ra", "re", "sa",
    "se", "si", "so", "su", "ta", "te", "ti", "to", "tu", "uc", "uf", "ul", "um", "un", "ur",
    "us", "ut", "uy", "uz", "va", "ve", "ya", "ye", "yi", "yo", "yu", "za", "ze",
    "ben", "sen", "biz", "siz", "var", "yok", "cok", "her", "bir", "iki", "son", "ilk", "iyi",
    "yeni", "eski", "buyuk", "kucuk", "uzun", "kisa", "tam", "hic", "ama", "fakat", "veya",
    "icin", "gore", "kadar", "gibi", "sonra", "once", "simdi", "yarin", "bugun", "dun",
    "bey", "hanim", "film", "dizi", "oyun", "sirket", "ekip", "marka", "ulus", "halk", "ordu",
    "van", "agri", "mus", "kars", "batman", "mersin", "denizli", "sivas", "corum",
    "can", "deniz", "gunes", "yol", "baris", "umut", "kaya", "demir", "aslan", "kurt",
    "sahin", "kartal", "dogan", "yildiz", "cicek", "gul", "tas", "bas", "elma", "uzum",
    "the", "and", "for", "with", "from", "that", "this", "not", "are", "was", "were",
    "java", "ruby", "rust", "swift", "apple", "edge", "word", "code", "steam", "oracle",
    "discord", "docker", "notion", "linear", "meta", "slack", "zoom", "signal", "teams",
    "matrix", "chrome", "brave", "arc", "halo", "doom", "portal", "her", "dark", "house",
    "friends", "dunes", "dune", "mars", "rome", "troy",
}

SPARQL_QUERIES: list[tuple[str, str]] = [
    (
        "countries",
        """
        SELECT DISTINCT ?label ?sitelinks WHERE {
          ?item wdt:P31 wd:Q6256 ;
                wikibase:sitelinks ?sitelinks .
          FILTER(?sitelinks >= 60)
          ?item rdfs:label ?label .
          FILTER(LANG(?label) = "tr")
        }
        ORDER BY DESC(?sitelinks)
        LIMIT 300
        """,
    ),
    (
        "turkish_provinces_and_districts",
        """
        SELECT DISTINCT ?label ?sitelinks WHERE {
          { ?item wdt:P31 wd:Q48336 . }
          UNION
          { ?item wdt:P31 wd:Q1147395 . }
          ?item wdt:P17 wd:Q43 ;
                wikibase:sitelinks ?sitelinks .
          FILTER(?sitelinks >= 5)
          ?item rdfs:label ?label .
          FILTER(LANG(?label) = "tr")
        }
        ORDER BY DESC(?sitelinks)
        LIMIT 1200
        """,
    ),
    (
        "world_major_cities",
        """
        SELECT DISTINCT ?label ?sitelinks WHERE {
          ?item wdt:P31 wd:Q515 ;
                wikibase:sitelinks ?sitelinks .
          FILTER(?sitelinks >= 60)
          ?item rdfs:label ?label .
          FILTER(LANG(?label) IN ("tr", "en"))
        }
        ORDER BY DESC(?sitelinks)
        LIMIT 1200
        """,
    ),
    (
        "tech_companies_and_brands",
        """
        SELECT DISTINCT ?label ?sitelinks WHERE {
          { ?item wdt:P452 wd:Q11661 ; wikibase:sitelinks ?sitelinks . FILTER(?sitelinks >= 18) }
          UNION
          { ?item wdt:P452 wd:Q880371 ; wikibase:sitelinks ?sitelinks . FILTER(?sitelinks >= 18) }
          UNION
          { ?item wdt:P31 wd:Q4830453 ; wikibase:sitelinks ?sitelinks . FILTER(?sitelinks >= 50) }
          ?item rdfs:label ?label .
          FILTER(LANG(?label) = "en")
        }
        ORDER BY DESC(?sitelinks)
        LIMIT 1800
        """,
    ),
    (
        "software_languages_platforms",
        """
        SELECT DISTINCT ?label ?sitelinks WHERE {
          VALUES ?cls { wd:Q7397 wd:Q9143 wd:Q9135 wd:Q35127 wd:Q166142 }
          ?item wdt:P31 ?cls ;
                wikibase:sitelinks ?sitelinks .
          FILTER(?sitelinks >= 25)
          ?item rdfs:label ?label .
          FILTER(LANG(?label) = "en")
        }
        ORDER BY DESC(?sitelinks)
        LIMIT 2000
        """,
    ),
    (
        "video_games_and_media",
        """
        SELECT DISTINCT ?label ?sitelinks WHERE {
          VALUES ?cls { wd:Q7889 wd:Q5398426 wd:Q11424 }
          ?item wdt:P31 ?cls ;
                wikibase:sitelinks ?sitelinks .
          FILTER(?sitelinks >= 45)
          ?item rdfs:label ?label .
          FILTER(LANG(?label) = "en")
        }
        ORDER BY DESC(?sitelinks)
        LIMIT 2000
        """,
    ),
    (
        "turkish_institutions_and_culture",
        """
        SELECT DISTINCT ?label ?sitelinks WHERE {
          VALUES ?cls { wd:Q3918 wd:Q1248784 wd:Q33506 wd:Q476028 }
          ?item wdt:P31 ?cls ;
                wdt:P17 wd:Q43 ;
                wikibase:sitelinks ?sitelinks .
          FILTER(?sitelinks >= 8)
          ?item rdfs:label ?label .
          FILTER(LANG(?label) = "tr")
        }
        ORDER BY DESC(?sitelinks)
        LIMIT 800
        """,
    ),
    (
        "turkish_notable_people",
        """
        SELECT DISTINCT ?label ?sitelinks WHERE {
          ?item wdt:P31 wd:Q5 ;
                wdt:P27 wd:Q43 ;
                wikibase:sitelinks ?sitelinks .
          FILTER(?sitelinks >= 18)
          ?item rdfs:label ?label .
          FILTER(LANG(?label) = "tr")
        }
        ORDER BY DESC(?sitelinks)
        LIMIT 1200
        """,
    ),
    (
        "global_historical_people",
        """
        SELECT DISTINCT ?label ?sitelinks WHERE {
          ?item wdt:P31 wd:Q5 ;
                wikibase:sitelinks ?sitelinks .
          FILTER(?sitelinks >= 110)
          ?item rdfs:label ?label .
          FILTER(LANG(?label) IN ("tr", "en"))
        }
        ORDER BY DESC(?sitelinks)
        LIMIT 1500
        """,
    ),
    (
        "turkish_given_names",
        """
        SELECT DISTINCT ?label ?sitelinks WHERE {
          VALUES ?cls { wd:Q202444 wd:Q12308941 wd:Q11879590 }
          ?item wdt:P31 ?cls ;
                wdt:P407 wd:Q256 ;
                wikibase:sitelinks ?sitelinks .
          FILTER(?sitelinks >= 3)
          ?item rdfs:label ?label .
          FILTER(LANG(?label) = "tr")
        }
        ORDER BY DESC(?sitelinks)
        LIMIT 600
        """,
    ),
]

SINGLE_WORD_RE = re.compile(r"^[A-Za-zÇĞİÖŞÜçğıöşü]+$")


def turkish_lower(text: str) -> str:
    return text.replace("I", "ı").replace("İ", "i").lower()


def ascii_fold(text: str) -> str:
    return (
        text.replace("ç", "c")
        .replace("Ç", "C")
        .replace("ğ", "g")
        .replace("Ğ", "G")
        .replace("ı", "i")
        .replace("İ", "I")
        .replace("ö", "o")
        .replace("Ö", "O")
        .replace("ş", "s")
        .replace("Ş", "S")
        .replace("ü", "u")
        .replace("Ü", "U")
    )


def strip_parenthetical(label: str) -> str:
    # Drop Wikipedia-style disambiguation suffixes like "Apple (company)" -> reject instead of guessing
    return label.strip()


def run_sparql(query: str) -> list[tuple[str, int]]:
    encoded = urllib.parse.urlencode({"query": query, "format": "json"})
    url = f"{SPARQL_ENDPOINT}?{encoded}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/sparql-results+json"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=45) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
            rows: list[tuple[str, int]] = []
            for binding in payload.get("results", {}).get("bindings", []):
                lbl = binding.get("label", {}).get("value", "").strip()
                sl = int(binding.get("sitelinks", {}).get("value", 0))
                if lbl:
                    rows.append((lbl, sl))
            return rows
        except Exception as exc:
            if attempt == 2:
                print(f"[warn] SPARQL query failed after 3 attempts: {exc}")
                return []
            time.sleep(2 * (attempt + 1))
    return []


def fetch_wikidata(cache_path: Path) -> list[dict]:
    records: list[dict] = []
    for name, query in SPARQL_QUERIES:
        print(f"Fetching Wikidata CC0 slice '{name}'...")
        rows = run_sparql(query)
        print(f"  -> {len(rows)} labels received")
        for lbl, sl in rows:
            records.append({"label": lbl, "sitelinks": sl, "slice": name})
        time.sleep(0.5)

    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Saved {len(records)} raw Wikidata records to {cache_path}")
    return records


def load_dictionary_collision_sets() -> tuple[set[str], set[str], set[str]]:
    tr_exact: set[str] = set()
    tr_folded: set[str] = set()

    with TR_DIC_PATH.open("r", encoding="utf-8") as handle:
        for idx, line in enumerate(handle):
            if idx == 0 and line.strip().isdigit():
                continue
            stem = line.strip().split("/", 1)[0]
            if not stem:
                continue
            low = turkish_lower(stem)
            if low in HUNSPELL_PROPER_NOUN_ONLY_EXCEPTIONS:
                continue
            tr_exact.add(low)
            tr_folded.add(ascii_fold(low))

    en_words: set[str] = set()
    with EN_WORDLIST_PATH.open("r", encoding="utf-8") as handle:
        for line in handle:
            w = line.strip().lower()
            if w:
                en_words.add(w)

    return tr_exact, tr_folded, en_words


def is_valid_single_entity(word: str) -> bool:
    if len(word) < 2 or len(word) > 40:
        return False
    if not word[0].isupper():
        return False
    return bool(SINGLE_WORD_RE.match(word))


def is_valid_multi_word_entity(phrase: str) -> bool:
    if "(" in phrase or ")" in phrase or "[" in phrase or "]" in phrase:
        return False
    if any(ch in phrase for ch in ['"', "'", "“", "”", "`", "/", "\\", ":", ";", "!", "?"]):
        return False
    parts = phrase.split()
    if not (2 <= len(parts) <= 6):
        return False
    # Require at least 2 parts >= 2 chars or initial uppercase on the first token and >= 2 capitalized tokens
    if not parts[0][0].isupper():
        return False
    cap_count = sum(1 for p in parts if p[0].isupper())
    if cap_count < 2:
        return False
    # Reject generic descriptive subtitles like "List of ..." or "History of ..."
    if parts[0] in {"List", "History", "Economy", "Geography", "Culture", "Demographics", "Politics", "Index"}:
        return False
    if len(phrase) > 64:
        return False
    return True


def is_colliding(word: str, tr_exact: set[str], tr_folded: set[str], en_words: set[str]) -> bool:
    low = turkish_lower(word)
    fold = ascii_fold(low)
    ascii_lower = word.lower()

    if fold in COMMON_WORD_SAFETY_BLOCKLIST or low in COMMON_WORD_SAFETY_BLOCKLIST or ascii_lower in COMMON_WORD_SAFETY_BLOCKLIST:
        return True
    if low in tr_exact or fold in tr_folded:
        return True
    if word not in ENGLISH_NEWS_PROPER_NOUN_ALLOWLIST and (ascii_lower in en_words or fold in en_words):
        return True
    return False


def build_resources(records: Iterable[dict]) -> None:
    tr_exact, tr_folded, en_words = load_dictionary_collision_sets()

    tier2a: set[str] = set()
    tier2b: set[str] = set()
    tier3: set[str] = set()

    all_items: list[tuple[str, str]] = [(r["label"], r.get("slice", "wikidata")) for r in records]
    all_items.extend(CANONICAL_SUPPLEMENT)

    for raw_label, _slice_name in all_items:
        label = strip_parenthetical(" ".join(raw_label.split()))
        if not label:
            continue

        if " " in label:
            if is_valid_multi_word_entity(label):
                tier3.add(label)
            continue

        if not is_valid_single_entity(label):
            continue

        # Also split off personal names in `tr` multi-word names into single-token proper name candidates
        # only when not present directly? No — individual single-word entities come cleanly from direct labels.
        if is_colliding(label, tr_exact, tr_folded, en_words):
            tier2b.add(label)
        else:
            tier2a.add(label)

    # Also register each capitalized token >= 2 chars from Turkish/global person names into Tier2B/2A only
    # if it didn't collide, OR keep exact labels to avoid over-protecting surname noise.
    # Ensure zero overlap: Tier2A strictly disjoint from Tier2B (prefer conservative Tier2B on conflict).
    tier2a -= tier2b

    tier2a_sorted = sorted(tier2a)
    tier2b_sorted = sorted(tier2b)
    tier3_sorted = sorted(tier3)

    (RESOURCES_DIR / "tier2a_entities.txt").write_text("\n".join(tier2a_sorted) + "\n", encoding="utf-8")
    (RESOURCES_DIR / "tier2b_entities.txt").write_text("\n".join(tier2b_sorted) + "\n", encoding="utf-8")
    (RESOURCES_DIR / "tier3_entities.txt").write_text("\n".join(tier3_sorted) + "\n", encoding="utf-8")

    meta = {
        "schemaVersion": "1.0.0",
        "source": "Wikidata CC0 1.0 (https://query.wikidata.org/sparql) + curated canonical supplement",
        "license": "CC0-1.0",
        "collisionFilters": [
            "Sources/TitizCore/Resources/tr_TR.dic (exact & ASCII-folded)",
            "Sources/TitizCore/Resources/en_common_tech.txt",
            "COMMON_WORD_SAFETY_BLOCKLIST",
        ],
        "counts": {
            "tier2A": len(tier2a_sorted),
            "tier2B": len(tier2b_sorted),
            "tier3": len(tier3_sorted),
        },
        "specCheck": {
            "tier2A_present": [w for w in ["Intel", "Nvidia", "Spotify", "Netflix", "PlayStation", "Valorant", "Atatürk", "İstanbul"] if w in tier2a],
            "tier2B_present": [w for w in ["Can", "It", "Son", "Su", "Yol", "Güneş", "Swift", "Apple", "Deniz"] if w in tier2b],
            "tier3_present": [w for w in ["The Last of Us", "Red Dead Redemption", "Visual Studio Code"] if w in tier3],
        },
    }
    (RESOURCES_DIR / "wikidata_meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(meta, ensure_ascii=False, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description="Build Wikidata CC0 collision-filtered entity tables for Titiz.")
    parser.add_argument("--fetch", action="store_true", help="Fetch fresh Wikidata SPARQL CC0 records before filtering.")
    parser.add_argument(
        "--cache",
        type=Path,
        default=Path("/tmp/titiz-phase4-fetch/wikidata_raw.json"),
        help="Path to raw cached Wikidata JSON.",
    )
    args = parser.parse_args()

    if args.fetch:
        records = fetch_wikidata(args.cache)
    else:
        if not args.cache.exists():
            raise FileNotFoundError(f"Cache file not found at {args.cache}. Pass --fetch first.")
        records = json.loads(args.cache.read_text(encoding="utf-8"))

    build_resources(records)


if __name__ == "__main__":
    main()
