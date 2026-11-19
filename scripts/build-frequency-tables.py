#!/usr/bin/env python3
"""Builds compact Turkish unigram and quantized bigram frequency tables (tr_freq.bin).

Sources:
    Leipzig Corpora Collection (Wortschatz Leipzig), CC BY 4.0:
      - tur_wikipedia_2021_300K.tar.gz (300,000 sentences)
      - tur_news_2020_300K.tar.gz (300,000 sentences)

Usage:
    python3 scripts/build-frequency-tables.py --input-dir /tmp/titiz-phase3-fetch
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import json
import math
from pathlib import Path
import re
import struct
import tarfile
import unicodedata

ROOT = Path(__file__).resolve().parent.parent
RESOURCES_DIR = ROOT / "Sources" / "TitizCore" / "Resources"

MAGIC = b"TZFQ"
FORMAT_VERSION = 1

UNIGRAM_MIN_LOG10 = -8.0
UNIGRAM_MAX_LOG10 = -1.0
BIGRAM_MIN_LOG10 = -6.0
BIGRAM_MAX_LOG10 = 0.0
SMOOTHING_ALPHA = 0.5
SMOOTHING_VOCAB = 200.0

FNV1A_OFFSET_BASIS = 14695981039346656037
FNV1A_PRIME = 1099511628211

TR_LOWER_TRANS = str.maketrans(
    {
        "I": "ı",
        "İ": "i",
        "Ç": "ç",
        "Ğ": "ğ",
        "Ö": "ö",
        "Ş": "ş",
        "Ü": "ü",
        **{chr(c): chr(c + 32) for c in range(ord("A"), ord("Z") + 1) if chr(c) != "I"},
    }
)

ASCII_FOLD_TRANS = str.maketrans(
    {
        "ç": "c",
        "ğ": "g",
        "ı": "i",
        "ö": "o",
        "ş": "s",
        "ü": "u",
    }
)

TOKEN_RE = re.compile(r"[A-Za-zÇĞIİÖŞÜçğıöşü]+")


def turkish_lower(text: str) -> str:
    return unicodedata.normalize("NFC", text).translate(TR_LOWER_TRANS)


def ascii_fold_lower(word: str) -> str:
    return word.translate(ASCII_FOLD_TRANS)


def fnv1a_64(text: str) -> int:
    h = FNV1A_OFFSET_BASIS
    for byte in text.encode("utf-8"):
        h ^= byte
        h = (h * FNV1A_PRIME) & 0xFFFFFFFFFFFFFFFF
    return h


def quantize(value: float, min_val: float, max_val: float) -> int:
    clamped = min(max(value, min_val), max_val)
    scaled = (clamped - min_val) / (max_val - min_val) * 255.0
    return int(round(scaled))


def dequantize(q: int, min_val: float, max_val: float) -> float:
    return min_val + (q / 255.0) * (max_val - min_val)


def process_tarball(tar_path: Path, unigrams: Counter[str], bigrams: Counter[tuple[str, str]]) -> tuple[int, int]:
    sentences_count = 0
    tokens_count = 0
    with tarfile.open(tar_path, "r:gz") as tf:
        sent_member = next((m for m in tf.getmembers() if m.name.endswith("-sentences.txt")), None)
        if sent_member is None:
            raise FileNotFoundError(f"No *-sentences.txt inside {tar_path}")
        stream = tf.extractfile(sent_member)
        assert stream is not None
        for raw_line in stream:
            line = raw_line.decode("utf-8", errors="ignore").rstrip("\r\n")
            if "\t" in line:
                _, sentence = line.split("\t", 1)
            else:
                sentence = line
            sentence = unicodedata.normalize("NFC", sentence)
            tokens = [turkish_lower(m.group(0)) for m in TOKEN_RE.finditer(sentence)]
            if not tokens:
                continue
            sentences_count += 1
            tokens_count += len(tokens)
            unigrams.update(tokens)
            for idx in range(len(tokens) - 1):
                bigrams[(tokens[idx], tokens[idx + 1])] += 1
    return sentences_count, tokens_count


def main() -> None:
    parser = argparse.ArgumentParser(description="Build compact Turkish unigram + quantized bigram frequency table.")
    parser.add_argument("--input-dir", type=Path, required=True, help="Directory containing Leipzig tarballs.")
    parser.add_argument("--max-unigrams", type=int, default=150_000)
    parser.add_argument("--max-bigrams", type=int, default=400_000)
    args = parser.parse_args()

    en_path = RESOURCES_DIR / "en_common_tech.txt"
    if not en_path.exists():
        raise FileNotFoundError(f"Missing {en_path}; run scripts/build-character-assets.py first.")
    english_words = {line.strip() for line in en_path.read_text(encoding="utf-8").splitlines() if line.strip()}

    corpora = [
        ("tur_wikipedia_2021_300K", args.input_dir / "tur_wikipedia_2021_300K.tar.gz"),
        ("tur_news_2020_300K", args.input_dir / "tur_news_2020_300K.tar.gz"),
    ]

    raw_unigrams: Counter[str] = Counter()
    raw_bigrams: Counter[tuple[str, str]] = Counter()
    total_sentences = 0
    total_tokens = 0

    for label, path in corpora:
        s_cnt, t_cnt = process_tarball(path, raw_unigrams, raw_bigrams)
        total_sentences += s_cnt
        total_tokens += t_cnt
        print(f"Processed {label}: {s_cnt:,} sentences, {t_cnt:,} tokens")

    # Keep top unigrams with count >= 2
    eligible_unigrams = [(w, c) for w, c in raw_unigrams.most_common() if c >= 2]
    kept_unigrams = dict(eligible_unigrams[: args.max_unigrams])

    folded_groups: dict[str, set[str]] = defaultdict(set)
    for w in kept_unigrams:
        folded_groups[ascii_fold_lower(w)].add(w)

    ambiguous_words: set[str] = set()
    for w in kept_unigrams:
        folded = ascii_fold_lower(w)
        if len(folded_groups[folded]) >= 2 or folded in english_words:
            ambiguous_words.add(w)

    eligible_bigrams = [
        (pair, c)
        for pair, c in raw_bigrams.most_common()
        if c >= 2 and pair[0] in kept_unigrams and pair[1] in kept_unigrams
        and (pair[0] in ambiguous_words or pair[1] in ambiguous_words)
    ]
    kept_bigrams = eligible_bigrams[: args.max_bigrams]

    # Deduplicate by FNV-1a 64-bit hash (highest frequency wins on any collision)
    unigram_table: dict[int, int] = {}
    for w, c in sorted(kept_unigrams.items(), key=lambda kv: -kv[1]):
        h = fnv1a_64(w)
        if h not in unigram_table:
            log_p = math.log10(c / float(total_tokens))
            unigram_table[h] = quantize(log_p, UNIGRAM_MIN_LOG10, UNIGRAM_MAX_LOG10)

    bigram_table: dict[int, int] = {}
    for (w1, w2), c in kept_bigrams:
        h = fnv1a_64(f"{w1}\t{w2}")
        if h not in bigram_table:
            denom = kept_unigrams[w1] + SMOOTHING_ALPHA * SMOOTHING_VOCAB
            cond_log_p = math.log10((c + SMOOTHING_ALPHA) / denom)
            bigram_table[h] = quantize(cond_log_p, BIGRAM_MIN_LOG10, BIGRAM_MAX_LOG10)

    sorted_unigrams = sorted(unigram_table.items(), key=lambda kv: kv[0])
    sorted_bigrams = sorted(bigram_table.items(), key=lambda kv: kv[0])

    bin_path = RESOURCES_DIR / "tr_freq.bin"
    with bin_path.open("wb") as f:
        f.write(struct.pack("<4sHHII", MAGIC, FORMAT_VERSION, 0, len(sorted_unigrams), len(sorted_bigrams)))
        for h, q in sorted_unigrams:
            f.write(struct.pack("<QB", h, q))
        for h, q in sorted_bigrams:
            f.write(struct.pack("<QB", h, q))

    def lookup_uni(word: str) -> float:
        q = unigram_table.get(fnv1a_64(word))
        return dequantize(q, UNIGRAM_MIN_LOG10, UNIGRAM_MAX_LOG10) if q is not None else -8.2

    def lookup_bi(w1: str, w2: str) -> float | None:
        q = bigram_table.get(fnv1a_64(f"{w1}\t{w2}"))
        return dequantize(q, BIGRAM_MIN_LOG10, BIGRAM_MAX_LOG10) if q is not None else None

    sanity_checks = {
        "yarın_uni": round(lookup_uni("yarın"), 3),
        "yarin_uni": round(lookup_uni("yarin"), 3),
        "iş_uni": round(lookup_uni("iş"), 3),
        "is_uni": round(lookup_uni("is"), 3),
        "akşam_uni": round(lookup_uni("akşam"), 3),
        "aksam_uni": round(lookup_uni("aksam"), 3),
        "dün_uni": round(lookup_uni("dün"), 3),
        "dun_uni": round(lookup_uni("dun"), 3),
        "hazır_uni": round(lookup_uni("hazır"), 3),
        "hazir_uni": round(lookup_uni("hazir"), 3),
        "şok_uni": round(lookup_uni("şok"), 3),
        "sok_uni": round(lookup_uni("sok"), 3),
        "işe_uni": round(lookup_uni("işe"), 3),
        "ise_uni": round(lookup_uni("ise"), 3),
        "işim_uni": round(lookup_uni("işim"), 3),
        "isim_uni": round(lookup_uni("isim"), 3),
        "işe|gittim_bi": lookup_bi("işe", "gittim"),
        "ise|gittim_bi": lookup_bi("ise", "gittim"),
        "işim|var_bi": lookup_bi("işim", "var"),
        "isim|var_bi": lookup_bi("isim", "var"),
        "güzel|ise_bi": lookup_bi("güzel", "ise"),
        "güzel|işe_bi": lookup_bi("güzel", "işe"),
        "basın_uni": round(lookup_uni("basın"), 3),
    }

    meta = {
        "formatVersion": FORMAT_VERSION,
        "hashAlgorithm": "FNV-1a-64-UTF8",
        "corpora": [
            {
                "name": "Leipzig Corpora Collection — tur_wikipedia_2021_300K",
                "url": "https://downloads.wortschatz-leipzig.de/corpora/tur_wikipedia_2021_300K.tar.gz",
                "license": "CC BY 4.0",
            },
            {
                "name": "Leipzig Corpora Collection — tur_news_2020_300K",
                "url": "https://downloads.wortschatz-leipzig.de/corpora/tur_news_2020_300K.tar.gz",
                "license": "CC BY 4.0",
            },
        ],
        "totalSentences": total_sentences,
        "totalTokens": total_tokens,
        "unigramCount": len(sorted_unigrams),
        "bigramCount": len(sorted_bigrams),
        "binarySizeBytes": bin_path.stat().st_size,
        "quantization": {
            "unigramMinLog10": UNIGRAM_MIN_LOG10,
            "unigramMaxLog10": UNIGRAM_MAX_LOG10,
            "bigramMinLog10": BIGRAM_MIN_LOG10,
            "bigramMaxLog10": BIGRAM_MAX_LOG10,
            "bigramSmoothingAlpha": SMOOTHING_ALPHA,
            "bigramSmoothingVocab": SMOOTHING_VOCAB,
        },
        "sanityChecks": sanity_checks,
    }

    meta_path = RESOURCES_DIR / "tr_freq_meta.json"
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(
        f"Wrote {bin_path}: {len(sorted_unigrams):,} unigrams, {len(sorted_bigrams):,} bigrams "
        f"({bin_path.stat().st_size / (1024 * 1024):.2f} MiB)"
    )
    print("Sanity checks:", json.dumps(sanity_checks, ensure_ascii=False))


if __name__ == "__main__":
    main()
