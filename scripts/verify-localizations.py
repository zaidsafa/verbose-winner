#!/usr/bin/env python3
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Pinbook" / "Localizable.xcstrings"
LOCALES = {
    "ar", "de", "es", "fr", "hi", "id", "it", "ja", "ko", "pt-BR",
    "ru", "tr", "ur", "zh-Hans", "zh-Hant",
}
CHECKPOINT_KEYS = {
    "Account deletion started",
    "Account ready: create a team or open an invitation",
    "Action completed",
    "Account access",
    "Account access could not be confirmed. Close this screen before signing in again.",
    "Account cleanup could not be confirmed. Do not retry this invitation yet.",
    "Account deletion is still in progress",
    "Block user",
    "Check delivery status",
    "Checking account access…",
    "Continue to sign in",
    "Create a team",
    "Create member invitation",
    "Connected",
    "Delivery updated",
    "Delete account",
    "Harassment",
    "Illegal activity",
    "Inbox refreshed",
    "Invitation ready",
    "Note ID",
    "No team notes",
    "Note sent",
    "Other",
    "Privacy Policy",
    "Reason",
    "Recovery completed",
    "Refresh now",
    "Report note",
    "Report user",
    "Retry pending note",
    "Review invitation",
    "Setup could not continue. Close this screen and reopen the invitation.",
    "Safety action completed",
    "Scam",
    "Sign in with Apple",
    "Sign in with Google",
    "Signed in",
    "Spam",
    "Status",
    "Team workspace",
    "Team created",
    "Team Terms",
    "Terms accepted",
    "User ID",
    "Unblock user",
}

def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)

catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
strings = catalog.get("strings", {})
missing_keys = sorted(CHECKPOINT_KEYS - strings.keys())
if missing_keys:
    fail("missing checkpoint keys: " + ", ".join(missing_keys))

for key, entry in strings.items():
    localizations = entry.get("localizations", {})
    for locale in LOCALES:
        unit = localizations.get(locale, {}).get("stringUnit", {})
        if unit.get("state") != "translated" or not unit.get("value"):
            fail(f"{key!r} is incomplete for {locale}")

print(f"PASS: {len(strings)} keys complete across English plus {len(LOCALES)} translations")
