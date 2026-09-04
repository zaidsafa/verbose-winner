# iOS durable team-join recovery — inactive

Updated 2026-09-04. `TeamJoinStore` records recoverable membership intent. It does
not grant current membership, account access or permission to share existing notes.
No normal navigation, HTTP, background work or provider is activated here.

The 2026-09-05 explicit retry extension adds read-only `retryCandidate` and
consented `beginExplicitRetry` with original identity/hash and a new CAS generation;
it preserves PENDING on null/error/uncertain write. Its consent deadline is checked
around native commit/reread, with current session/device/monotonic checks retained
by the membership owner. See TEAM_MEMBERSHIP_RETRY_IOS.md for contract and evidence.

## Exact pending intent and recovery

After separate explicit membership consent and current account/device/epoch checks,
the membership coordinator must call `begin` BEFORE one `teams/accept`. It records
the exact trusted HTTPS origin, account, authority epoch, team, device enrollment,
offered MEMBER/REVIEWER role, invitation hash, random local generation, PENDING phase
and checked time. It does not save the raw invitation, account credentials, identity
proof, private device key, financial records or portable recovery keys.

The invitation hash is SHA256 of UTF-8 `pinbook-team-invite-v1`, a NUL byte and the
canonical invitation code, matching the Android domain convention. It is a local
correlation value, not encryption, anonymization or independent authorization.

An existing pending/confirmed team record cannot be overwritten by another invite.
A failed or uncertain local write never permits dispatch; it may already have
committed. Reopen distinguishes absent metadata from a whole pending/confirmed
record. It does not automatically retry, clear the intent or erase another team.
Post-write current-generation, clock and invitation-expiry checks can also refuse
dispatch while leaving committed pending metadata intact.

`beginRecovery` requires the exact previously displayed/read record and commits a
fresh local generation before a new `teams/current` request. It preserves team,
enrollment, role, invitation hash and any previous membership revision. Recovery
does not need the original invitation to remain available, valid or unconsumed.

Only a freshly fetched, exactly bound accept/current result can `confirm` the same
local generation. Account, team, enrollment and role must match; revision must be
safe, nonnegative and not lower than the previously confirmed revision. Confirmation
rotates the local generation. Late responses for an earlier recovery are rejected.
There is no null/error confirmation or automatic retry/deletion operation.

`list` is read-only, scoped and deterministically sorted by team ID. Its results
are LOCAL RECOVERY METADATA, not proof that membership is still active. The host
must label them accordingly, invalidate stale selections, and check the current
session/device and server before protected actions.

## Native storage and boundaries

Separate data-protection Keychain generic-password item:

- Service: `com.zaidsafa.pinbook.ios.team-join-custody.v1`.
- Account: `bounded-join-index`.
- Accessibility: `WhenPasscodeSetThisDeviceOnly`; synchronization false.

No existing account, device or backup item is changed. Loading validates protection
attributes, exact bounded data, and the stored SHA256 payload selector. Add and
updates are single native operations; updates match the exact prior payload hash.
Each write rotates both index and record UUIDs. Concurrent owners cannot silently
overwrite the same team or discard another team's newly committed index update.
A stale compare-and-swap fails, without retrying an unknown side effect.

The payload hash is a compare-and-swap selector/consistency check, NOT a MAC or
independent rollback protection. Protection relies on the system Keychain. All
record schemas, duplicate decoded keys/rows, canonical IDs/UUIDs/numbers, phase
invariants and scope limits are checked by the strict decoder. Corruption or locked
access fails without clearing other records or creating a replacement key.

Limits are at most eight origin/account/epoch scopes, ten teams per scope, eighty
records overall and 64 KiB of encoded metadata. Long identifiers can hit the byte
limit before the row limit. Capacity reserves future timestamp/revision digit
growth and PENDING→CONFIRMED text growth, so an admitted record retains room for
recovery/confirmation at capacity. Existing generations can still rotate when the
row limit is reached. No automatic scope retirement or eviction is implemented.

Current-account/device checks and monotonic deadlines belong to the next retained
membership owner, not this synchronous storage layer. Its driver must run native
storage work off the UI executor and await real completion even after cancellation.
Separate account, device, join and remote transactions are not one atomic lock;
post-commit cancellation/sign-out may leave metadata but must not return a current
authenticated success. Metadata must never be imported as remote authority.

## Validation and next stage

Synthetic tests cover read-only reopen, expired-link recovery without a raw code,
explicit consent, exact origin/account/epoch/enrollment/role, forged/stale snapshots,
regressed membership revisions, uncertain writes, post-commit expiry including slow
reads, rollback/cancellation, locked/corrupt/oversized storage, row and byte capacity,
future growth at capacity, concurrent same/different-team owners, and the native
Keychain adapter's policy/CAS through a synthetic SecItem API.

Final full core **189/189 PASS**,16.171s:
`/private/tmp/pinbook-ios-join-store-final-verified-core.log`.
This includes twelve join-store cases. Two earlier complete regressions failed
in different localhost TLS tests; subsequent passes do not diagnose/fix those
intermittent failures. They remain explicit final-release validation caveats.
Final Simulator build-for-testing and unsigned iPhone Release also pass:
`/private/tmp/pinbook-ios-join-store-verified-test-build.log` and
`/private/tmp/pinbook-ios-join-store-verified-release.log`. Compilation only;
no new app-host/UI execution or signed distribution artifact.

Native Keychain size/performance/CAS under actual OS contention, passcode removal,
lock/unlock, restore and retirement need physical acceptance. Synthetic storage is
not proof of device protection. No hardware, app-host UI or live service claim is
made. See VALIDATION.md for exact runs, including intermittent TLS regression errors.

The retained current-session/current-registered-device owner is now implemented
and documented in TEAM_MEMBERSHIP_JOIN_IOS.md, with fresh lookup, one-use separate
membership consent, durable begin, single accept and read-only current-membership
recovery. Explicit reattempt after eligible-pending reconciliation still requires
a designed confirmation path (null does not prove no late commit); never
silently clear a pending record to make retry work. Then add localized screens and
session/lifecycle host wiring. Keep all other FINAL_UPDATE_CHECKLIST.md features,
provider/crypto/staging/physical gates, and the existing TestFlight build unchanged.
