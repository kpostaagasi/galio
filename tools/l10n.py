#!/usr/bin/env python3
"""Regenerate Galio/Resources/Localizable.xcstrings from Swift sources.

Turkish is the development language: every Turkish UI literal is a key. English translations
live in tools/l10n/en.json ({"<turkish key>": "<english>"}). Run after changing UI strings:
    python3 tools/l10n.py          # writes the catalog, lists keys missing an English value
    python3 tools/l10n.py --check  # exit 1 if any key lacks a translation
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "Galio"
EN = ROOT / "tools" / "l10n" / "en.json"
OUT = ROOT / "Galio" / "Resources" / "Localizable.xcstrings"

LIT = r'"((?:[^"\\]|\\.)*)"'
PATTERNS = [
    re.compile(r'\b(?:Text|Button|Label|Toggle|Section|Picker|TextField|LabeledContent|Menu|GroupBox|Link|ContentUnavailableView|SecureField|Tab)\(\s*' + LIT),
    re.compile(r'\.(?:help|navigationTitle|accessibilityLabel|accessibilityHint|accessibilityValue|searchable\(text:[^,]+,\s*prompt)\(\s*' + LIT),
    re.compile(r'\bLoc\.tr\(\s*' + LIT),
    re.compile(r'\b(?:titleKey|labelKey|prompt):\s*(?:Text\()?' + LIT),
    re.compile(r'\bdescription:\s*Text\(\s*' + LIT),
    re.compile(r'confirmationDialog\(\s*' + LIT),
    re.compile(r'\.alert\(\s*' + LIT),
]


def swift_key(raw: str) -> str:
    # Swift escapes -> real characters; string interpolation becomes %@ (UI code only interpolates Strings).
    s = re.sub(r'\\\((?:[^()]|\([^()]*\))*\)', '%@', raw)
    return s.replace('\\"', '"').replace('\\n', '\n').replace('\\\\', '\\')


def extract():
    keys = {}
    for path in sorted(SRC.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for pat in PATTERNS:
            for m in pat.finditer(text):
                key = swift_key(m.group(1))
                if any(ch.isalpha() for ch in key):
                    keys.setdefault(key, str(path.relative_to(ROOT)))
    return keys


def main():
    check = "--check" in sys.argv
    keys = extract()
    en = json.loads(EN.read_text(encoding="utf-8")) if EN.exists() else {}
    missing = [k for k in keys if k not in en]
    strings = {}
    for k in sorted(keys):
        entry = {"extractionState": "manual"}
        if k in en:
            entry["localizations"] = {"en": {"stringUnit": {"state": "translated", "value": en[k]}}}
        strings[k] = entry
    catalog = {"sourceLanguage": "tr", "strings": strings, "version": "1.0"}
    OUT.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    unused = [k for k in en if k not in keys]
    print(f"{len(keys)} keys, {len(missing)} missing English, {len(unused)} unused translations")
    for k in missing:
        print("MISSING:", json.dumps(k, ensure_ascii=False), "  <-", keys[k])
    if check and missing:
        sys.exit(1)


if __name__ == "__main__":
    main()
