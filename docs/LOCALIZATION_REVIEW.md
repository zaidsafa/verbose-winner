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

Generated initial drafts are authorized. They are not professional or native-reviewed
translations. Xcode's `translated` string-unit state means a value exists, not that
a person reviewed it. Record language, screen, current text, proposed correction,
and the relevant key when collecting tester feedback.

`scripts/localization_drafts.py --check` is an offline completeness/format-token
check. Generation is a separate, opt-in operation that sends only interface text to
the draft service used for Android and caches plain-data responses. It must never
read or send financial records, backups, credentials, or user-entered content.

## Current boundary

The language behavior update passed 37 simulator tests and 9 core tests on 2026-09-04,
plus an unsigned iPhone Release build. Full 16-language draft
generation is pending explicit approval for the interface-text payload and third-party
destination; the bulk request was rejected by the approval safeguard before execution.
The existing English, Arabic, and Simplified Chinese catalogs remain the current
language coverage. Only compiled languages appear in the selector; the target
16-language enum is not a claim of shipped coverage. Verify the existing coverage
with `python3 scripts/localization_drafts.py --check --locales ar zh-Hans`.
Do not publish or claim complete parity until coverage, layout,
and exact-build physical acceptance have passed.

The simulator caught and the implementation fixed two runtime-refresh issues:
separate UserDefaults instances did not refresh all observers, and a presented
navigation host cached its previous title locale. The shared preference instance,
explicit presentation environment, and selector-only host refresh passed the final
suite. Neither fix resets financial records or the onboarding page index.
