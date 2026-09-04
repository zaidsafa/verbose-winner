# Account-session custody — inactive iOS implementation

`TeamAccountSessionStore` is deliberately separate from archive recovery keys,
SwiftData, Files exports, user defaults and portable backups. It is not yet wired
to provider UI, a refresh coordinator or normal navigation. Construction reads or
writes nothing. No account/provider/endpoint is invented.

## Storage and consent

- One generic-password item, fixed service
  `com.zaidsafa.pinbook.ios.team-account-session.v1`, fixed active-session slot.
  A validated trusted HTTPS origin and provider profile scope the protected record.
  Loading with another scope fails without deleting or replacing anything.
- Public construction always uses the data-protection Keychain,
  `WhenPasscodeSetThisDeviceOnly`, synchronizable=false. Device passcode required;
  unlocked-only; no backup or synchronization. Removing/resetting the passcode can
  invalidate account sessions and require sign-in again. There is no weaker fallback.
- Existing archive recovery keys remain `WhenUnlockedThisDeviceOnly` and are NOT
  migrated, deleted or reused for session protection. “ThisDeviceOnly” alone is
  not a no-backup guarantee: same-device restores differ from migration. See
  [Apple's Keychain accessibility guidance](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)
  and [Platform Security](https://support.apple.com/en-ie/guide/security/secb0694df1a/1/web/1).
- Initial save requires explicit consent and uses atomic add-only semantics.
  Existing sessions are not silently overwritten or switched. Missing, unavailable,
  corrupt, mismatched and expired are distinct failures. Local sign-out/removal
  requires explicit consent and an exact generation; it is NOT server revocation.
- Protected payload is capped at4096bytes and validates exact fields, version,
  canonical token shape, scope, generation, JS-safe timestamps and expiry ordering.
  Initial/new pair permits at most905s access and30days+5s family lifetime. Usable
  access must be unexpired. Refresh can use an expired access token only while its
  family is still valid. Clock rollback before the persisted observation is rejected;
  this is not a trusted-clock or device-restore-authority implementation.

## Refresh transition

1. Read the active snapshot under the expected scope.
2. Before ANY HTTP dispatch, `beginRefresh` atomically replaces payload+random
   generation with `refreshPending`. The persisted marker contains scope, account,
   family and expiry, but neither old access nor refresh token. A volatile lease with
   the old pair is returned only after this write reports success.
3. The future coordinator may dispatch that lease once. A pending record cannot
   produce credentials or another lease. Competing handles using the old generation
   lose. Cancellation, process death, unknown remote result or interrupted provider
   work must not reconstruct/replay the previous refresh.
4. `completeRefresh` validates both new tokens against BOTH old tokens and retains
   account/family/absolute expiry. One generation-matched SecItemUpdate replaces
   marker with the entire new pair and a new generation. The operation cannot update
   a newer login or resurrect an explicitly removed session.

The old random generation is queried via `kSecAttrGeneric`; both payload and new
generation are updated in one Security call. There is no read-then-unconditional
write window. Random generation metadata contains no credential/account identifier.
See [Apple DTS guidance on generic-password matching](https://developer.apple.com/forums/thread/724013).

## Ambiguous storage result

- A failed marker call returns no lease, so the coordinator must not dispatch.
  Reopened storage may still be active (write did not commit) or pending (commit
  succeeded but acknowledgment was lost). The caller must not assume rollback.
- After remote refresh, a failed replacement may leave pending OR the complete
  new pair. The failed call does not return success. A later explicit read can
  distinguish these atomic states; it must never replay old tokens. A complete new
  pair is storage reconciliation, not confirmation that an old HTTP retry is safe.
- No post-write cancellation is presented as rollback. Pre-cancelled calls do not
  mutate. Swift copies and old encrypted Keychain pages are not claimed physically
  erased. Current low-level APIs still require one-owner flow/orchestration.

## Evidence and open gates

Seven synthetic Keychain tests pass, covering passcode-only attributes, consent,
add-only behavior, marker token removal/reopen, ambiguous writes before/after commit,
eight competing refresh starts with one winner, stale completion/sign-out after a
new login, scope/corruption/read failures, expiry/clock checks and pre-cancellation.

A DEBUG-only test constructor uses an isolated `pinbook.session-test.<UUID>` service
and WhenUnlockedThisDeviceOnly solely to test real SecItem generation matching in
Simulator. It never migrates a production item and is absent from Release. This
cannot establish physical passcode-only/no-backup/locked-device acceptance. Actual
SecItem generation query/update and stale-operation rejection passed in0.006s and
the test entry was removed. Full core88/88 and iPhone app-host111 passes plus one
hardware file-protection skip; unsigned Release passed. See `VALIDATION.md`.

Still required: serialized refresh manager with cancellation/late-result ownership,
provider/challenge/exchange integration, explicit account switching and revocation,
current restore authority, enrollment/roles, locked/background UX, physical Keychain
acceptance and approved staging. No normal navigation activation or TestFlight update.
