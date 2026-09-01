# Validation plan

## Automated on every coherent milestone

- Run `swift test` for backup compatibility, merge behavior, and currency-safe money.
- Build the iOS app unsigned against the iOS simulator SDK.
- Compile and run the in-memory SwiftData tests for clean bootstrap, persistence, settlements, and currency-separated totals.
- Run `git diff --check` and confirm the working tree contains no generated build output or credentials.

## Visual and accessibility acceptance

- Inspect Expenses, Summary, Noted, grouped Options, add-expense, and partial-payment flows on an iPhone simulator.
- Check Paper glass, Clean ledger, Soft pastel, Editorial, and Night ink in light/dark appearances.
- Check native Liquid Glass controls while scrolling and during sheet presentation; information cards must remain stable and legible.
- Check Reduce Transparency and Increase Contrast, and verify that no state depends only on color.
- Exercise Dynamic Type through the accessibility sizes without clipped amount or action rows.
- Review VoiceOver labels/order and minimum control hit areas.
- Run in Arabic to verify right-to-left order, leading/trailing alignment, and mirrored navigation.
- Test empty, long-text, large-value, zero-decimal, two-decimal, and three-decimal currency states.

## Completed simulator matrix — 2026-09-01

The matrix uses `-PinbookFixture populated`, an in-memory SwiftData store available only in Debug builds. Production bootstrap remains empty apart from its default book and appearance settings. Deterministic launch arguments also select the initial tab, skin, and theme without writing sample records to the persistent store.

| Evidence | Scenario | Result |
| --- | --- | --- |
| `docs/evidence/pinbook-populated-paper.png` | Paper Glass, light, open expenses | Partial payment and remaining CNY balance visible; USD and three-decimal KWD cards remain separate. |
| `docs/evidence/pinbook-summary-soft-pastel.png` | Soft Pastel, light, Summary | Open/noted counts and CNY, KWD, USD totals are legible without a rectangular page backing. |
| `docs/evidence/pinbook-noted-night-ink.png` | Night Ink, dark, Noted | Populated recoverable item is legible on the stable dark surface. |
| `docs/evidence/pinbook-options-grouped.png` | Paper Glass, grouped Options | Personalize, Data, and Device groups are readable and unfinished capabilities remain explicit. |
| `docs/evidence/pinbook-populated-ar.png` | Arabic RTL, Paper Glass | Navigation, actions, and shell copy are Arabic and mirrored; financial values use bidirectional isolation. Fixture record content intentionally remains test-authored English. |
| `docs/evidence/pinbook-dynamic-type-axxxl.png` | Accessibility extra-extra-large | The title becomes inline, metadata and actions stack vertically, Quick Add yields to the toolbar Add action, and the first card has no clipped balance or action. |
| `docs/evidence/pinbook-increased-contrast-reduced-transparency.png` | Increase Contrast plus Reduce Transparency | Stable cards gain a stronger outline and native glass controls use an opaque, legible fallback. |

The Simulator accessibility tree exposed the open-expense elements in logical order: Add, heading, purpose, counterparty, labeled remaining balance/value, date, category, Payment, and Mark noted. Card actions have a minimum 44-point height; navigation uses the native tab bar. This verifies labels and structural order, not spoken VoiceOver output, rotor behavior, or physical-device focus behavior.

### Automated evidence

- Swift package: 5/5 tests passed.
- iOS simulator suite: 5/5 tests passed, including clean production bootstrap, persistence/partial payment, currency-separated totals, launch-argument parsing, and deterministic fixture contents.
- Unsigned Debug and Release generic iOS Simulator builds passed against SDK 26.5 with deployment target 26.1.
- The Debug fixture is excluded from Release compilation by `#if DEBUG`; the Release build passed after this boundary was added.

## Release boundary

Simulator builds and static inspection do not prove physical-device behavior, Apple signing, Google OAuth, Drive transfer, iCloud, notifications, file import/export, or App Store review readiness. Each implemented integration needs its own end-to-end acceptance before any release claim.
