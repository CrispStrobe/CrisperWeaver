#!/usr/bin/env python3
"""DEPRECATED — do not use. Kept only as a record of the one-off
migration that turned the old compiled-in `baked_models_catalog.dart`
into `assets/models/catalog.json`.

That Dart file no longer exists, so this script now exits 1 on the
"not found" check rather than silently emitting a wrong catalogue. The
live generator is `scripts/bake_models_catalog.dart`
(`dart run scripts/bake_models_catalog.dart`), which probes the HF API
and writes the JSON directly.

Note the shape difference that made this converter lossy in the first
place: `PARAM_RE` below matches only strings, ints, bools and
`ModelKind.*` — it has never been able to parse a list, so
`languages:` and `companions:` were dropped from every entry it
converted (issue #35).

Parse baked_models_catalog.dart and emit assets/models/catalog.json.

This avoids needing the Flutter SDK — it uses regex to extract each
ModelDefinition(...) block and its named parameters, then writes them
as a JSON array whose shape matches ModelDefinition.toJson().
"""

import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DART_FILE = REPO / "lib" / "services" / "baked_models_catalog.dart"
OUT_FILE = REPO / "assets" / "models" / "catalog.json"

# Match each ModelDefinition(...) constructor call (possibly spanning many lines).
# We rely on the closing ");", which always appears at column-2 indentation.
ENTRY_RE = re.compile(
    r"ModelDefinition\((.*?)\),",
    re.DOTALL,
)

# Match a single named parameter.  Handles:
#   name: 'value',          — string
#   sizeBytes: 12345,       — int
#   kind: ModelKind.asr,    — enum
#   requiresVoice: true,    — bool
#   checksum: '',            — empty string
PARAM_RE = re.compile(
    r"(\w+):\s*"
    r"("
    r"'(?:[^'\\]|\\.)*'"   # single-quoted string
    r"|ModelKind\.\w+"      # enum value
    r"|true|false"          # bool
    r"|\d+"                 # int
    r")"
)


def parse_entry(body: str) -> dict:
    """Parse the inside of a ModelDefinition(...) into a JSON-compatible dict."""
    params = {}
    for m in PARAM_RE.finditer(body):
        key = m.group(1)
        raw = m.group(2)
        if raw.startswith("'"):
            value = raw[1:-1].replace("\\'", "'")
        elif raw.startswith("ModelKind."):
            value = raw.split(".")[1]  # e.g. "asr"
        elif raw in ("true", "false"):
            value = raw == "true"
        else:
            value = int(raw)
        params[key] = value

    # Build the output dict in the same order as toJson().
    entry: dict = {
        "name": params["name"],
        "displayName": params["displayName"],
        "fileName": params["fileName"],
        "url": params["url"],
        "sizeBytes": params["sizeBytes"],
        "checksum": params.get("checksum", ""),
        "description": params["description"],
        "quantization": params.get("quantization", "f16"),
        "backend": params.get("backend", "whisper"),
        "kind": params.get("kind", "asr"),
    }

    # Optional fields — only include when present (matches toJson() behaviour).
    if "companions" in params:
        # Not used in the baked file today, but handle just in case.
        entry["companions"] = params["companions"]
    if "languages" in params:
        entry["languages"] = params["languages"]
    if "license" in params:
        entry["license"] = params["license"]
    if params.get("requiresVoice"):
        entry["requiresVoice"] = True

    return entry


def main() -> None:
    if not DART_FILE.exists():
        print(f"ERROR: {DART_FILE} not found", file=sys.stderr)
        sys.exit(1)

    text = DART_FILE.read_text()
    entries = []
    for m in ENTRY_RE.finditer(text):
        try:
            entries.append(parse_entry(m.group(1)))
        except (KeyError, ValueError) as exc:
            # Print the offending block for debugging, then skip.
            print(f"WARNING: skipping entry — {exc}\n{m.group(0)[:200]}", file=sys.stderr)

    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUT_FILE.write_text(json.dumps(entries, indent=2, ensure_ascii=False) + "\n")
    print(f"Wrote {len(entries)} entries to {OUT_FILE}")
    if len(entries) < 300:
        print(f"WARNING: only {len(entries)} entries (expected >300)", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
