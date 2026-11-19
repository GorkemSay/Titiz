#!/usr/bin/env python3
"""Builds GPA pattern table (gpa_patterns.json) and English common+tech wordlist (en_common_tech.txt).

Usage:
    python3 scripts/build-character-assets.py --input-dir /tmp/titiz-phase3-fetch
"""

from __future__ import annotations

import argparse
import json
import re
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOURCES_DIR = ROOT / "Sources" / "TitizCore" / "Resources"

CURATED_TECH_SUPPLEMENT = {
    "analytics", "android", "api", "appkit", "apple", "async", "auth", "autocomplete",
    "autofill", "avatar", "await", "backend", "backlog", "badge", "benchmark", "beta",
    "biometric", "bluetooth", "bookmark", "boolean", "bootstrap", "branch", "breakpoint",
    "browser", "buffer", "build", "bundle", "byte", "cache", "callback", "camelcase",
    "canvas", "captcha", "changelog", "checkbox", "checksum", "cli", "clipboard", "cloud",
    "cluster", "codec", "codebase", "commit", "compiler", "config", "container", "cookie",
    "cors", "cpu", "cron", "crypto", "css", "csv", "cursor", "darkmode", "dashboard",
    "database", "debug", "debugger", "decoder", "deploy", "deployment", "desktop", "devops",
    "diff", "digest", "docker", "domain", "download", "driver", "dropdown", "dylib",
    "emoji", "encoder", "encryption", "endpoint", "enum", "eslint", "eval", "fallback",
    "feedback", "fetch", "filesystem", "filter", "firebase", "firmware", "flag", "flexbox",
    "folder", "font", "footer", "framework", "frontend", "fullstack", "gateway", "git",
    "github", "gitlab", "gpu", "graphql", "grep", "gzip", "hash", "hashtag", "header",
    "headless", "heap", "hotfix", "hotkey", "html", "http", "https", "icloud", "icon",
    "ide", "identifier", "indexer", "inline", "input", "installer", "interface", "ios",
    "ip", "ipad", "iphone", "iterator", "javascript", "json", "jwt", "kernel", "keychain",
    "keyframe", "keyword", "kotlin", "kubernetes", "latency", "layout", "lexer", "library",
    "linter", "linux", "localhost", "lockfile", "log", "login", "logout", "lookup",
    "macos", "macbook", "macro", "malloc", "manifest", "markdown", "menubar", "merge",
    "metadata", "metrics", "microservice", "middleware", "migration", "modal", "module",
    "monorepo", "mutex", "namespace", "native", "navbar", "nested", "network", "nginx",
    "nodejs", "npm", "nullable", "oauth", "offline", "onboarding", "opensource", "opcode",
    "overlay", "override", "package", "padding", "pagination", "parser", "pascalcase",
    "passkey", "patch", "payload", "pdf", "pipeline", "pixel", "placeholder", "plist",
    "plugin", "pointer", "popover", "popup", "postgres", "prefix", "preview", "profiler",
    "prompt", "protobuf", "proxy", "pull", "push", "python", "query", "queue", "quicklook",
    "readme", "rebase", "refactor", "regex", "register", "release", "remote", "render",
    "repo", "repository", "request", "resolver", "response", "retry", "rollback", "router",
    "runtime", "safari", "sandbox", "schema", "screenshot", "scroll", "scrollbar", "sdk",
    "search", "secret", "selector", "semver", "sendable", "serializer", "server", "session",
    "setter", "sha", "shell", "shortcut", "sidebar", "signature", "slider", "slug",
    "snapshot", "snippet", "socket", "software", "sort", "sql", "sqlite", "ssh", "ssl",
    "stack", "staging", "startup", "stateful", "stateless", "status", "stdin", "stdout",
    "storage", "stream", "string", "struct", "stylesheet", "subagent", "subdomain",
    "submit", "suffix", "svg", "swift", "swiftpm", "swiftui", "symlink", "sync", "syntax",
    "tab", "tablet", "tag", "tarball", "target", "telemetry", "template", "terminal",
    "testflight", "thread", "throttle", "thumbnail", "timeout", "timestamp", "tls",
    "toggle", "token", "tokenizer", "toml", "toolbar", "tooltip", "trace", "trackpad",
    "tuple", "typescript", "ui", "unicode", "unigram", "unlock", "update", "upload",
    "upstream", "uri", "url", "utf", "utf8", "uuid", "ux", "validator", "variable",
    "vector", "vendor", "version", "viewport", "virtual", "vpn", "webhook", "webkit",
    "websocket", "widget", "wifi", "window", "wordlist", "workflow", "workspace",
    "wrapper", "xcode", "xml", "yaml", "zip", "zsh",
}

TURKISH_ASCII_EXCLUSIONS = {
    "disari", "cikacagim", "icin", "cocuklar", "yagmur", "cok", "bugun", "cunku",
    "turkce", "ogrenci", "sehir", "calismak", "guncellemesi", "sonrasi", "topladik",
    "cikmadi", "aksam", "gorusuruz", "tesekkurler", "ozel", "hazirlik", "duzenli",
    "calisiyor", "soyledi", "dosyasi", "uzerinden", "uzerinde", "icinde", "yanitini",
    "yapistirip", "dugmesine", "paylasti", "geldimi", "varmi", "ciktimi", "gordunmu",
    "olmusmu", "hersey", "birsey", "kutuphanesinde", "arkadasim", "guzel", "aldim",
}


def parse_turkish_el_patterns(el_path: Path) -> dict[str, dict[str, int]]:
    """Extracts the 6 GPA decision lists (`c, g, i, o, s, u`) from Deniz Yuret's `turkish.el`."""
    content = el_path.read_text(encoding="utf-8")
    marker = "(defvar turkish-pattern-table"
    start_idx = content.find(marker)
    if start_idx == -1:
        raise ValueError("Could not find turkish-pattern-table in turkish.el")

    # Narrow to the quoted alist inside `(turkish-make-pattern-table '((?c ... ) ...))`
    quote_idx = content.find("'((?", start_idx)
    if quote_idx == -1:
        raise ValueError("Could not find pattern alist start in turkish.el")

    src = content[quote_idx + 1 :]
    pos = 0
    n = len(src)
    tables: dict[str, dict[str, int]] = {}

    def skip_ws():
        nonlocal pos
        while pos < n and src[pos] in " \t\r\n":
            pos += 1

    def read_lisp_string() -> str:
        nonlocal pos
        assert src[pos] == '"'
        pos += 1
        chars: list[str] = []
        while pos < n:
            ch = src[pos]
            pos += 1
            if ch == '"':
                return "".join(chars)
            if ch == "\\" and pos < n:
                esc = src[pos]
                pos += 1
                chars.append(esc)
            else:
                chars.append(ch)
        raise ValueError("Unterminated Lisp string in turkish.el")

    skip_ws()
    assert src[pos] == "("
    pos += 1

    while pos < n:
        skip_ws()
        if src[pos] == ")":
            break
        assert src[pos] == "("
        pos += 1
        skip_ws()
        assert src[pos] == "?"
        pos += 1
        letter = src[pos]
        pos += 1
        if letter not in {"c", "g", "i", "o", "s", "u"}:
            raise ValueError(f"Unexpected pattern table key: {letter!r}")

        entries: dict[str, int] = {}
        rank = 1
        while pos < n:
            skip_ws()
            if src[pos] == ")":
                pos += 1
                break
            assert src[pos] == "(", f"Expected '(' at offset {pos}, got {src[pos:pos+20]!r}"
            pos += 1
            skip_ws()
            pattern = read_lisp_string()
            skip_ws()
            positive = False
            if src[pos] == ".":
                pos += 1
                skip_ws()
                if src[pos] == "t":
                    positive = True
                    pos += 1
                skip_ws()
            assert src[pos] == ")", f"Expected ')' after pattern {pattern!r}, got {src[pos:pos+20]!r}"
            pos += 1

            # Replicate turkish-pattern-hash: first pattern occurrence sets rank and polarity.
            if pattern not in entries:
                entries[pattern] = rank if positive else -rank
            rank += 1

        tables[letter] = entries

    expected_letters = {"c", "g", "i", "o", "s", "u"}
    if set(tables.keys()) != expected_letters:
        raise ValueError(f"Missing GPA tables: expected {expected_letters}, got {set(tables.keys())}")

    return tables


def build_english_wordlist(master_path: Path, eng_tar_path: Path, target_size: int = 40_000) -> list[str]:
    """Builds a clean ~40k common + technical English wordlist from MIT Wordlist + CC BY 4.0 Leipzig frequencies."""
    ascii_word_re = re.compile(r"^[a-z]{2,}$")

    master_words: set[str] = set()
    with master_path.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            w = line.strip().lower()
            if ascii_word_re.match(w):
                master_words.add(w)

    freq_counts: dict[str, int] = {}
    with tarfile.open(eng_tar_path, "r:gz") as tf:
        words_member = next(
            (m for m in tf.getmembers() if m.name.endswith("-words.txt")),
            None,
        )
        if words_member is None:
            raise FileNotFoundError("No *-words.txt found inside eng_news tarball")
        extracted = tf.extractfile(words_member)
        assert extracted is not None
        for raw_line in extracted:
            parts = raw_line.decode("utf-8", errors="ignore").rstrip("\r\n").split("\t")
            if len(parts) < 3:
                continue
            w = parts[1].strip().lower()
            if not ascii_word_re.match(w) or w not in master_words:
                continue
            try:
                count = int(parts[2])
            except ValueError:
                continue
            freq_counts[w] = freq_counts.get(w, 0) + count

    ranked_words = sorted(freq_counts.items(), key=lambda kv: (-kv[1], kv[0]))
    selected = {w for w, _ in ranked_words[:target_size]}
    selected.update(w for w in CURATED_TECH_SUPPLEMENT if ascii_word_re.match(w))
    selected.difference_update(TURKISH_ASCII_EXCLUSIONS)

    return sorted(selected)


def main() -> None:
    parser = argparse.ArgumentParser(description="Build Titiz Phase 3 GPA pattern & English wordlist resources.")
    parser.add_argument("--input-dir", type=Path, required=True, help="Directory with fetched upstream files.")
    args = parser.parse_args()

    RESOURCES_DIR.mkdir(parents=True, exist_ok=True)

    el_path = args.input_dir / "turkish.el"
    patterns = parse_turkish_el_patterns(el_path)
    gpa_out = RESOURCES_DIR / "gpa_patterns.json"
    gpa_out.write_text(json.dumps(patterns, ensure_ascii=True, separators=(",", ":")), encoding="utf-8")

    master_path = args.input_dir / "wordlist-master.txt"
    eng_tar_path = args.input_dir / "eng_news_2020_100K.tar.gz"
    english_words = build_english_wordlist(master_path, eng_tar_path, target_size=40_000)

    if not (30_000 <= len(english_words) <= 50_000):
        raise AssertionError(f"Expected 30k-50k English words, got {len(english_words)}")

    en_out = RESOURCES_DIR / "en_common_tech.txt"
    en_out.write_text("\n".join(english_words) + "\n", encoding="utf-8")

    english_set = set(english_words)
    for required in ("driver", "feedback", "search", "is", "on", "son", "can", "gun", "basin", "us", "of", "swift", "apple"):
        if required not in english_set:
            raise AssertionError(f"Expected required English word '{required}' missing from wordlist")

    for forbidden in ("disari", "cikacagim", "icin", "cocuklar", "yagmur", "cok", "bugun", "cunku"):
        if forbidden in english_set:
            raise AssertionError(f"Turkish-only word '{forbidden}' leaked into English wordlist")

    print(f"Wrote {gpa_out}: " + ", ".join(f"{k}={len(v)}" for k, v in sorted(patterns.items())))
    print(f"Wrote {en_out}: {len(english_words)} words ({en_out.stat().st_size / 1024:.1f} KiB)")


if __name__ == "__main__":
    main()
