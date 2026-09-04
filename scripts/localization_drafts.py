#!/usr/bin/env python3
"""Offline import/check of assistant-authored drafts. No network access.

Authoring files use stable numbered English keys from --export-keys and one
index|translation line per key. Existing translations are preserved unless
--replace is explicit. Xcode's translated state does not imply native review.
"""
import argparse
import collections
import json
from pathlib import Path
import plistlib
import re

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Pinbook/Localizable.xcstrings"
LOCALES = ["ar", "tr", "zh-Hans", "zh-Hant", "es", "fr", "de", "pt-BR",
           "hi", "id", "ja", "ko", "ru", "it", "ur"]
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|ld|@|d|f|s)")

def signature(text):
    return collections.Counter(re.sub(r"%\d+\$", "%", p) for p in PLACEHOLDER.findall(text))

def validate_value(key, value):
    if not value.strip() or signature(key) != signature(value):
        raise ValueError(f"Empty value or format mismatch: {key!r}: {value!r}")
    if re.search(r"987659|<<<|TODO|TRANSLATE_ME", value):
        raise ValueError(f"Unexpected draft marker: {key!r}")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--export-keys", type=Path)
    parser.add_argument("--import-dir", type=Path)
    parser.add_argument("--replace", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--check-built-app", type=Path,
                        help="Compare compiled app and widget strings with this catalog")
    parser.add_argument("--locales", nargs="+", choices=LOCALES)
    args = parser.parse_args()
    catalog = json.loads(CATALOG.read_text())
    strings = catalog["strings"]
    if args.export_keys:
        args.export_keys.mkdir(parents=True, exist_ok=True)
        (args.export_keys / "keys.json").write_text(json.dumps(list(strings), ensure_ascii=False, indent=2) + "\n")
        print(f"Exported {len(strings)} stable source keys")
        return
    if args.import_dir:
        keys = json.loads((args.import_dir / "keys.json").read_text())
        if len(keys) != len(set(keys)) or set(keys) != set(strings):
            raise SystemExit("Source keys changed; reconcile drafts before import")
        for locale in args.locales or LOCALES:
            path = args.import_dir / f"{locale}.txt"
            if not path.exists():
                continue
            entries = {}
            for line in path.read_text().splitlines():
                if not line.strip():
                    continue
                index, value = line.split("|", 1)
                index = int(index)
                if index in entries or not 0 <= index < len(keys):
                    raise SystemExit(f"Duplicate/out-of-range index: {locale}/{index}")
                validate_value(keys[index], value)
                entries[index] = value
            if set(entries) != set(range(len(keys))):
                raise SystemExit(f"{locale}: missing indexes {set(range(len(keys))) - set(entries)}")
            for index, value in entries.items():
                translations = strings[keys[index]].setdefault("localizations", {})
                if locale in translations and not args.replace:
                    continue
                translations[locale] = {"stringUnit": {"state": "translated", "value": value}}
            print(f"Imported {locale}: {len(entries)} validated drafts")
        CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    failures = []
    for key, entry in strings.items():
        for locale in args.locales or LOCALES:
            value = entry.get("localizations", {}).get(locale, {}).get("stringUnit", {}).get("value", "")
            try:
                validate_value(key, value)
            except ValueError as error:
                failures.append(f"{locale}: {error}")
    if failures:
        raise SystemExit(f"FAIL: {len(failures)} missing/invalid translations\n" + "\n".join(failures[:20]))
    print(f"PASS: {len(strings)} keys × {len(args.locales or LOCALES)} translated locales + English source; format tokens intact")
    if args.check_built_app:
        for product in [args.check_built_app, args.check_built_app / "PlugIns/PinbookWidgets.appex"]:
            for locale in ["en"] + (args.locales or LOCALES):
                path = product / f"{locale}.lproj/Localizable.strings"
                values = plistlib.loads(path.read_bytes())
                expected = {
                    key: key if locale == "en" else entry["localizations"][locale]["stringUnit"]["value"]
                    for key, entry in strings.items()
                }
                # Xcode omits source-language entries with no explicit en value;
                # those deliberately fall back to the English key in the binary.
                matches = (all(key in expected and value == expected[key]
                               for key, value in values.items())
                           if locale == "en" else values == expected)
                if not matches:
                    raise SystemExit(f"Compiled catalog mismatch: {path}")
            print(f"PASS: {product.name} compiled translations exactly match source")

if __name__ == "__main__":
    main()
