# Team recovery-key text v1

Agreed with Android on 2026-09-04. This is a human-readable representation of the
existing 32-byte archive recovery key, not a new encryption, authentication,
enrollment or archive-wire protocol. Received-text archive v1 is unchanged.

## Canonical form

- Exactly 64 lowercase ASCII hexadecimal digits, two per byte, in byte order.
- No prefix, separators, spaces, BOM or newline in canonical Copy/export output.
- Input accepts uppercase/lowercase ASCII hex and leading/trailing ASCII whitespace
  only: HT, LF, VT, FF, CR and SPACE (09, 0a, 0b, 0c, 0d and 20 hex).
- After trimming only those edge bytes, length must be exactly 64 bytes.
- Reject internal whitespace, group separators, Unicode whitespace/confusables,
  zero-width and bidi marks, non-hex characters and any alternative encoding.
- Do not normalize Unicode, silently repair characters or derive a key from a password.
- The parser does not generate/store/replace keys or validate account ownership.
  Archive authentication and expected-account validation must still succeed.

## User interface and custody

Display may visually group characters, but Copy and export must yield canonical
ungrouped text. Clearly tell users not to type grouping separators.

Key export is a distinct **plaintext secret file**, never bundled with an archive.
Before revealing/copying/exporting, explain that anyone possessing the recovery key
and encrypted archive can decrypt it; keep them separately in safe locations.
Do not automatically upload either to a shared cloud destination or claim that
saving a file proves off-device recovery. No key, file path, clipboard content or
archive plaintext belongs in analytics, diagnostics or logs.

An unavailable/corrupt device key is not a missing key; never replace it implicitly.
Imported keys must first authenticate the selected archive/account before an
explicit decision to retain a previously missing key locally. Never overwrite
existing custody. Recovery restores local archive records only, not remote access,
team membership, ACKs, live MLS ratchets or enrollment.

## Shared public fixtures

`Tests/PinbookCoreTests/Fixtures/team-recovery-key-text-v1.json` contains only public
test keys and positive/negative parser examples. Its canonical outputs are not
production-safe secrets. Android will mirror these bytes and report its independent
parser results. No cross-platform execution pass is claimed by this document alone.

## Current validation

- Fixture SHA-256: `68b29e62f3a9bcb0b38d08c26669f7c58a85756f405eb08d00bfe85591cbcad5`.
- Swift `TeamRecoveryKeyText` passes five positive and fourteen negative fixtures,
  every byte value across eight 32-byte keys, and rejection of non-256-bit keys.
  Core run at this parser checkpoint: 52/52 passed; later session checkpoint: 54/54.
- Android reports 102/102 JVM plus lint/debug passes at
  `fc7a0e263f3584f5eb11236020ede77b6df5fbe6`. The iOS task independently reviewed
  parser source SHA `eea8428817e05ce3ff9733360ef23ebc55a339aa4db3c52b81185dc05cc6aa6b`
  for ASCII/length/normalization semantics, but did not independently run Android.
- Swift returns a SymmetricKey and best-effort clears temporary mutable bytes.
  Immutable Swift/Kotlin strings and runtime copies cannot be guaranteed erased.
