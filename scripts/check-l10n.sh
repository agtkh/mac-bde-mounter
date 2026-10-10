#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""
Localization (i18n) verification script.
Validates that all Xcode String Catalogs (.xcstrings) have 100% complete
translations across all target languages, with valid states and matching format specifiers.
"""

import sys
import json
import re
from pathlib import Path

REQUIRED_LANGUAGES = ["en", "ja"]

def check_catalog(file_path: Path) -> int:
    print(f"Checking catalog: {file_path.relative_to(Path.cwd())}")
    if not file_path.exists():
        print(f"  ❌ File not found: {file_path}")
        return 1

    try:
        with open(file_path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"  ❌ Invalid JSON: {e}")
        return 1

    source_lang = data.get("sourceLanguage", "en")
    strings = data.get("strings", {})

    total_keys = len(strings)
    errors = 0
    warnings = 0

    print(f"  Source language: '{source_lang}', Total keys: {total_keys}")

    for key, item in strings.items():
        localizations = item.get("localizations", {})

        for lang in REQUIRED_LANGUAGES:
            if lang not in localizations:
                print(f"  ❌ Missing '{lang}' localization for key: '{key}'")
                errors += 1
                continue

            entry = localizations[lang]
            unit = entry.get("stringUnit", {})
            state = unit.get("state")
            val = unit.get("value", "")

            if state != "translated":
                print(f"  ❌ Key '{key}' [{lang}] has invalid state: '{state}' (expected 'translated')")
                errors += 1

            if not val or not val.strip():
                print(f"  ❌ Key '{key}' [{lang}] has empty translation value")
                errors += 1

            # Check format specifier parity between source and translation
            if lang != source_lang:
                source_unit = localizations.get(source_lang, {}).get("stringUnit", {})
                source_val = source_unit.get("value", key)
                source_specs = re.findall(r"%[@dfsu]", source_val)
                target_specs = re.findall(r"%[@dfsu]", val)
                if len(source_specs) != len(target_specs):
                    print(f"  ⚠️ Warning: Placeholder mismatch in '{key}' [{lang}]: source has {len(source_specs)}, target has {len(target_specs)}")
                    warnings += 1

    if errors == 0:
        print(f"  ✅ All {total_keys} keys verified for {REQUIRED_LANGUAGES} ({warnings} warnings)\n")
        return 0
    else:
        print(f"  ❌ Found {errors} error(s) in catalog\n")
        return 1

def main():
    repo_root = Path(__file__).resolve().parent.parent
    catalogs = [
        repo_root / "App" / "Resources" / "Localizable.xcstrings",
        repo_root / "App" / "Resources" / "InfoPlist.xcstrings",
    ]

    total_errors = 0
    for cat in catalogs:
        total_errors += check_catalog(cat)

    if total_errors > 0:
        print(f"Localization check FAILED with errors in {total_errors} catalog(s).")
        sys.exit(1)
    else:
        print("🎉 All localization catalogs passed validation successfully!")
        sys.exit(0)

if __name__ == "__main__":
    main()
