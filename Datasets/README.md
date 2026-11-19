# Titiz Evaluation Datasets

This directory stores development fixtures and schema definitions for `TitizEval`.

## Files

- `dev_cases.json` — Checked-in development and regression suite covering all three operating modes (`character`, `spelling`, `combined`), clean sentences, code-switched English+Turkish, colliding entities, minimal pairs, and fused clitics.
- `blind_cases.schema.json` — JSON Schema (Draft 2020-12) defining the exact format for held-out blind evaluation files.
- `blind_cases.json` *(gitignored, local-only)* — Optional user-supplied held-out blind dataset. Never commit blind datasets to git and never inspect individual blind examples when tuning thresholds or rules.

## Blind Evaluation Workflow

1. Create a local `Datasets/blind_cases.json` file conforming to `Datasets/blind_cases.schema.json`.
   - Ensure `expected` strings are UTF-8 NFC normalized.
   - For clean sentences (`isCleanSentence: true`), set `expected == input` and `expectedEdits: []`.
   - Ensure each entry in `expectedEdits` corresponds 1-to-1 to a minimal token diff between `input` and `expected`.
2. Run summary-only blind evaluation alongside the dev suite (or standalone):

```bash
# Run both dev and blind summary-only reports
swift run TitizEval --blind Datasets/blind_cases.json

# Run blind evaluation alone (per-case text payloads are strictly suppressed)
swift run TitizEval --blind Datasets/blind_cases.json --blind-only

# Enforce all Phase 2 quality and latency exit gates (exits with status 2 if any fail)
swift run TitizEval --blind Datasets/blind_cases.json --enforce-gates
```

When `--blind` is used, `TitizEval` automatically suppresses per-case `input` / `expected` / `actual` output in both text and JSON modes so developers and coding agents observe only aggregate quality and latency metrics.
