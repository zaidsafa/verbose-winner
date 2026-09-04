#!/usr/bin/env python3
"""Generate authorized localization drafts; --check is offline and never rewrites.

Uses the same draft service as Android 0.5.0 for iOS-only copy. Only app UI
strings are sent. Financial records, credentials, and user content are never read.
Network output is treated as plain data and validated before catalog insertion.
"""
import argparse
import collections
import hashlib
import html
import json
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Pinbook/Localizable.xcstrings"
SOURCE_COMMIT = "9ad28646f3ddb5ebfa874421b44e40b4cfda8a74"
LOCALES = {
    "ar": ("ar", "ar"), "tr": ("tr", "tr"),
    "zh-Hans": ("zh-rCN", "zh-CN"), "zh-Hant": ("zh-rTW", "zh-TW"),
    "es": ("es", "es"), "fr": ("fr", "fr"), "de": ("de", "de"),
    "pt-BR": ("pt-rBR", "pt-BR"), "hi": ("hi", "hi"),
    "id": ("in", "id"), "ja": ("ja", "ja"), "ko": ("ko", "ko"),
    "ru": ("ru", "ru"), "it": ("it", "it"), "ur": ("ur", "ur"),
}
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|ld|@|d|f|s)")
SEPARATOR = "<<<987654321>>>"
TERMS = ("Pinbook", "Liquid Glass", "iPhone", "PDF", "CSV", "OCR")


def signature(text):
    return collections.Counter(re.sub(r"%\d+\$", "%", p) for p in PLACEHOLDER.findall(text))


def validate_value(key, value, protected=False):
    if not value.strip() or signature(key) != signature(value):
        raise ValueError(f"Empty value or format mismatch: {key!r}: {value!r}")
    if "987659" in value or SEPARATOR in value:
        raise ValueError(f"Unrestored translation marker in {key!r}")
    for term in TERMS if protected else ():
        if term in key and term not in value:
            raise ValueError(f"Missing protected term {term!r}: {key!r}")


def protect(text):
    replacements = {}
    placeholders = PLACEHOLDER.findall(text)
    def replace(match):
        index = len(replacements)
        token = f"9876591{index:05d}56789"
        value = match.group()
        if len(placeholders) > 1 and "$" not in value:
            value = f"%{index + 1}${value[1:]}"
        replacements[token] = value
        return token
    text = PLACEHOLDER.sub(replace, text)
    for term in TERMS:
        if term in text:
            token = f"9876592{len(replacements):05d}56789"
            replacements[token] = term
            text = text.replace(term, token)
    return text, replacements


def request(text, target, cache):
    digest = hashlib.sha256((target + "\n" + text).encode()).hexdigest()
    path = cache / f"{digest}.json"
    if path.exists():
        return json.loads(path.read_text())
    for attempt in range(3):
        try:
            result = subprocess.run([
                "curl", "-fsS", "--max-time", "40", "--get",
                "--data-urlencode", "client=dict-chrome-ex",
                "--data-urlencode", "sl=en", "--data-urlencode", f"tl={target}",
                "--data-urlencode", "dt=t", "--data-urlencode", f"q={text}",
                "https://translate.googleapis.com/translate_a/single",
            ], capture_output=True, text=True, check=True)
            data = json.loads(result.stdout)
            translated = "".join(part[0] for part in data[0] if part and part[0])
            path.write_text(json.dumps(translated, ensure_ascii=False))
            return translated
        except (subprocess.CalledProcessError, ValueError, TypeError, IndexError):
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)


def translate_batch(keys, target, cache):
    safe = [protect(key) for key in keys]
    translated = request(f"\n{SEPARATOR}\n".join(item[0] for item in safe), target, cache)
    values = [part.strip() for part in translated.split(SEPARATOR)]
    if len(values) != len(keys):
        if len(keys) == 1:
            raise ValueError("Translation service changed separator")
        return [translate_batch([key], target, cache)[0] for key in keys]
    for index, (key, (_, replacements)) in enumerate(zip(keys, safe)):
        value = html.unescape(values[index])
        for token, original in replacements.items():
            value = value.replace(token, original)
        validate_value(key, value, protected=True)
        values[index] = value
    return values


def android_strings(repo, directory):
    result = subprocess.run([
        "git", "-C", str(repo), "show",
        f"{SOURCE_COMMIT}:app/src/main/res/{directory}/strings.xml",
    ], check=True, capture_output=True, text=True)
    return {node.attrib["name"]: "".join(node.itertext()).replace("\\'", "'")
            for node in ET.fromstring(result.stdout) if node.tag == "string"}


def put(strings, key, locale, value):
    validate_value(key, value)
    strings[key].setdefault("localizations", {})[locale] = {
        "stringUnit": {"state": "translated", "value": value}
    }


def save(catalog):
    CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--generate", action="store_true", help="Send missing UI strings to the draft service")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--locales", nargs="+", choices=list(LOCALES), help="Optional subset; default checks the full parity set")
    parser.add_argument("--android-repo", type=Path)
    parser.add_argument("--cache", type=Path, default=Path("/private/tmp/pinbook-localization-draft-cache"))
    args = parser.parse_args()
    catalog = json.loads(CATALOG.read_text())
    strings = catalog["strings"]
    if args.generate:
        for key in ["Language", "System Default", "Pinbook follows your iPhone language by default. You can change this at any time."]:
            strings.setdefault(key, {})
        args.cache.mkdir(parents=True, exist_ok=True)
        android_base = android_strings(args.android_repo, "values") if args.android_repo else {}
        source_names = {value: key for key, value in android_base.items()}
        source_names["System Default"] = "system_default"
        # Preserve all existing values, including the original Arabic/Chinese copy.
        for locale, (directory, target) in LOCALES.items():
            if args.locales and locale not in args.locales:
                continue
            existing = android_strings(args.android_repo, f"values-{directory}") if args.android_repo else {}
            missing = []
            reused = 0
            for key, entry in strings.items():
                if locale in entry.get("localizations", {}):
                    continue
                if key == "%lld" or key in ("Pinbook", "PDF and CSV", "PDF", "CSV", "OCR"):
                    if key == "PDF and CSV":
                        missing.append(key)
                    else:
                        put(strings, key, locale, key)
                elif source_names.get(key) in existing:
                    value = existing[source_names[key]]
                    try:
                        put(strings, key, locale, value)
                        reused += 1
                    except ValueError:
                        missing.append(key)
                else:
                    missing.append(key)
            # Small requests preserve item boundaries and remain resumable via cache.
            batch = []
            size = 0
            for key in missing:
                projected = len(protect(key)[0]) + len(SEPARATOR) + 2
                if batch and size + projected > 1400:
                    for source, value in zip(batch, translate_batch(batch, target, args.cache)):
                        put(strings, source, locale, value)
                    save(catalog)
                    batch, size = [], 0
                batch.append(key)
                size += projected
            if batch:
                for source, value in zip(batch, translate_batch(batch, target, args.cache)):
                    put(strings, source, locale, value)
            save(catalog)
            print(f"{locale}: reused {reused} Android values, generated {len(missing)} drafts", flush=True)
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
    print(f"PASS: {len(strings)} keys × {len(args.locales or LOCALES)} translated locales + English source; all format tokens intact")


if __name__ == "__main__":
    main()
