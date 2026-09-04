# iOS localization parity

## Contract

Android behavior reference: `9ad28646f3ddb5ebfa874421b44e40b4cfda8a74`, version 0.5.0.

- Follow the phone language by default; English is the unsupported-language fallback.
- Offer the same language destination from first-run introduction and Options.
- Persist an explicit choice; System Default returns to the phone's preferences.
- Target English, Arabic, Turkish, Simplified Chinese, Traditional Chinese, Spanish,
  French, German, Brazilian Portuguese, Hindi, Indonesian, Japanese, Korean,
  Russian, Italian, and Urdu. Chinese scripts remain separate. Arabic/Urdu mirror.
- Keep records, identifiers, backup fields, currency codes, and user-entered text
  unchanged by language selection. No SwiftData migration or destructive reset.
- Widget catalogs follow the widget/system locale. The in-app override is not
  shared with WidgetKit because the project does not use an App Group.
- Already scheduled notification text is not rewritten by a language switch;
  newly scheduled notifications use the selected language.

## Draft wording and feedback

Assistant-authored initial drafts are authorized. They are not professional or native-reviewed
translations. Xcode's `translated` string-unit state means a value exists, not that
a person reviewed it. Record language, screen, current text, proposed correction,
and the relevant key when collecting tester feedback.

The owner requested direct translation without Google on 2026-09-04. All 13 new
locales were authored directly by the assistant. No strings were sent to an
external translation service. `scripts/localization_drafts.py` now has no network
code: it exports indexed source keys, imports locally authored drafts, and checks
completeness/format tokens offline. A `translated` state is not a quality certificate.

For future corrections, edit the catalog directly with a focused patch, or use
`--export-keys DIR` and indexed `locale.txt` drafts (`index|translation`), followed
by `--import-dir DIR --locales LOCALE`. Existing translations are preserved unless
`--replace` is explicit. Run `python3 scripts/localization_drafts.py --check`.
Use `--check-built-app /absolute/path/Pinbook.app` to compare all compiled app and
widget values exactly against the source catalog. These tools never access
financial records, backups, credentials, or user-entered content.

## Current boundary

The catalog contains all 256 source keys in English plus 15 complete translations.
The 13 new locales are Turkish, Traditional Chinese, Spanish, French, German,
Brazilian Portuguese, Hindi, Indonesian, Japanese, Korean, Russian, Italian, and
Urdu. Existing Arabic values are preserved. Seven Simplified Chinese strings now
use “已归档” rather than “已结清”: archiving a record does not prove it was fully paid.
The project registers all locales and exposes them by their native names.

Catalog coverage does not prove natural wording or every screen layout. Physical
iPhone acceptance of this exact candidate and TestFlight distribution remain
pending; this is not a release claim. See `VALIDATION.md` for executed checks.

The simulator caught and the implementation fixed two runtime-refresh issues:
separate UserDefaults instances did not refresh all observers, and a presented
navigation host cached its previous title locale. The shared preference instance,
explicit presentation environment, and selector-only host refresh passed the final
suite. Neither fix resets financial records or the onboarding page index.
