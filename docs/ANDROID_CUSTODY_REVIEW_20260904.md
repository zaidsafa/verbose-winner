# Android recovery-key custody semantic review

Read-only review September 4, 2026. No Android source/test edits, test execution,
device access, provider activation or release. Android source is still evolving;
this review applies only to the hashes below, not an unverified later commit.

- TeamRecoveryKeyStore.kt SHA256:
  `cbdd85ac484bb0a4e45d37df1b7c67237cac4cb1980cfd5ab52b50c23c2bc392`
- AndroidTeamRecoveryKeys.kt SHA256:
  `6d4f22a0291146e15102778bbf7f84ffd89d06d934777bfea7bc7331b706f9b6`
- iOS comparison: local source `fac1834f4f1bf07942f8d2759fb5b4ec445ea503`.

## Aligned behavior

Explicit 32-byte first save; no overwrite; no generation during load; account and
archive-purpose isolation; no plaintext ordinary-file storage; inaccessible or
incomplete custody does not become successful empty setup. Android's two-store
design additionally rejects record/alias asymmetry and leaves uncertain aliases
alone, avoiding destructive cleanup after an uncertain write. The SQLite DB and
sidecars are excluded in both backup and device-transfer XML. This is source
configuration, not actual OS backup extraction evidence.

## Follow-ups sent directly to Android

1. **Access check after transaction completion.** `load` checks access inside the
   callback, then `SQLiteDatabase.endTransaction()` runs before plaintext is
   returned. A test driver can run the callback, change the access predicate to
   locked, then return; current source has no further access check. Recommended
   regression: present and missing records, lock transition during transaction
   completion, plus endTransaction failure wiping plaintext. Recheck after the
   transaction returns within the existing clearing catch path. This is a
   source-level control-flow finding, not an independently executed reproduction
   or proof of an exploitable device race. No function can promise the device will
   remain unlocked after return; future UI must clear transient keys on background.
2. **Different lock eligibility.** Android explicitly requires a configured secure
   screen lock. iOS uses WhenUnlockedThisDeviceOnly without an independent passcode
   prerequisite. Do not claim identical lock policy. Agree UI eligibility and
   lock-removal/lost-key messaging before activation; do not weaken Android merely
   to make the platforms appear equivalent.

Android's API35 floor is supported by official documentation describing Android
12-14 unlocked-device-key deletion/reauthorization bugs fixed in Android15. That
policy differs from per-use user authentication; no biometric, TEE or StrongBox
claim is justified by this source review.
[Android KeyGenParameterSpec documentation](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec.Builder#setUnlockedDeviceRequired(boolean)).

The owner sign-in choice remains in the existing Android task. No new owner
decision was requested by this bounded review; no interim TestFlight upload.

## Source-review closure of follow-up 1

Re-read the corrected implementation and regression tests later on September 4:

- Core SHA256 `19d176e473877305a9c2fcd5c1e3dfc4ba957d26cdc9c422d39da506385ec641`.
- Policy tests SHA256 `956e05816a38261ea74aba545cb00a1ac4efe6a1e235a222c4f190d3a4cdd162`.

The final access check now executes after transaction return, before either
plaintext or missing is returned. A finally/released guard clears available
decrypted bytes on unsuccessful exits, including Throwable exits. Deterministic
tests switch access to locked after the callback returns for present and missing
records; another test fails read-transaction completion and checks plaintext
clearing. The specific post-transaction source finding is **closed at these hashes**.

Android subsequently reported the final 98-test/lint/debug gate passed at
`0c9907c`, with both CI checks successful. This is peer execution evidence; no
independent Android tests were run for this closure. The screen-lock policy difference remains
an integration gate, as do physical lock behavior, key repair/rotation and UI.
