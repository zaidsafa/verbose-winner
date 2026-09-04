# iOS explicit membership confirmation and recovery — inactive

Updated 2026-09-04. `TeamMembershipJoin` connects the invitation handoff, current
account and registered-device custody, durable join metadata and typed HTTP client.
It is not linked from normal navigation and activates no live provider or service.

## Retained account and separate confirmation

One owner belongs to ONE exact access-only account ticket. Its origin/provider,
account/session IDs, token, expiry and local generation are immutable. Every
operation checks that exact ticket against current protected custody. Refresh,
sign-out or re-login invalidates this owner even if account IDs/tokens are reused.
The host must create a new owner and require fresh consent; it must not silently
continue a preview under the replacement account. Trusted authority epoch is
configuration, never an invitation/server payload choice.

`prepare(intent)` is an explicit, read-only review. It validates the intent's exact
account and canonical code/team/role/expiry, loads the current REGISTERED device,
checks its generation, performs a fresh exact-key server lookup and refuses an
existing local team record. It creates no account, key or membership metadata.
The returned preview contains account ID, team ID and offered role, but no code.

The screen must display those details and obtain NEW, initially unchecked membership
consent, separate from account-access consent. `join(preview, consent:)` accepts only
this owner's current opaque preview. A new review, cancellation or any join attempt
invalidates the old preview. Consent lasts at most five minutes of wall/monotonic
time and is clipped to invitation/account expiry. No automatic rearming on failure.

## One accept with durable uncertainty

Joining rechecks current account/device/time and performs another fresh lookup of
the SAME device key, enrollment and generation. Missing/foreign/denied registration
does not cause automatic device registration or key replacement. The owner then
commits the exact PENDING join record BEFORE dispatching one `teams/accept`.
Failure/uncertainty during that local commit means no HTTP dispatch, even if the
record was in fact saved. Account/device/time checks follow slow reads and writes.

The accept result must be exactly bound by the join store before confirmation.
Confirmation rotates the durable generation; the owner rereads it and checks the
account/device/time again, including the final parent-task handoff. Cancellation
or a changed account after commit may leave CONFIRMED metadata but cannot return a
current authenticated success. This is not remote rollback, nor an atomic transaction
across separate account/device/join stores and the server.

Only access tickets reach accept/current HTTP; refresh credentials are not carried
into membership transport. Existing snapshot-based internal callers remain thin
compatibility wrappers. All routes use the SAME retained client/request slot as
account and device flows, not independently constructed retrying clients.

## Recovery without the original invitation

`recover(teamID:)` uses this owner's still-current account, current registered device
and the persisted team/enrollment/role. It checks a fresh server registration,
commits a new recovery generation, then sends only `teams/current`. It works without
the original invitation code, including after process death or link expiry/consumption.
Exactly bound current membership confirms the new generation. Foreign roles,
regressed revisions, errors and denial cannot confirm or erase the record.

Recovery never calls `teams/accept`, silently clears PENDING or requests another
provider proof. A successful result is a freshly checked snapshot, not permanently
cached membership authority or proof that encrypted shared-note delivery is ready.
The UI must keep uncertainty visible after failure and never imply that existing
private notes were automatically shared.

## Lifecycle, clocks and storage work

The owner retains one unresolved operation. `cancelPendingMembership` clears
prepared consent, invalidates and cancels work, but keeps its busy slot until the
real child operation settles. `close` is permanent: no future work, and cleanup
waits for actual unresolved completion. Native store/key checks run through awaited
off-UI drivers; cancellation does not pretend an in-progress write never happened.

Each operation has a 125-second wall/monotonic acceptance budget. Consent has its
separate earlier deadline. Access lifetime is also anchored to monotonic time on
the start of the owner's first current-account check, BEFORE its potentially slow
storage read, and retained across operations,
so a stalled wall clock cannot continually renew this owner's access lifetime.
Clock rollback fails. Deadlines reject late results; they do not promise the OS can
force-stop a non-cooperative native call. The host must clear/close on background,
dismissal and session replacement, with its own late-UI generation checks.

No raw code in saved UI state/preferences/clipboard/logs; it is retained only in the
in-memory prepared task/intent until completion/clear. Dropping references does not
promise physical memory erasure. The core is not a screenshot-protection feature.

## Verification and remaining integration

Fifteen synthetic owner cases cover read-only preview, separate single-use/cross-
owner consent, current account/device replacement, wall/monotonic/rollback expiry,
missing/foreign/denied registration, uncertain marker writes, sign-out after slow
device checks/lookup/marker/confirmation, operation expiry during marker write,
cancelled delayed acceptance, close waiting for a real unresolved callback,
tokenless expired-link recovery, denied/foreign/regressed recovery and monotonic
access expiry across operations and during the first slow account read. They use
synthetic account/Keychain/device adapters.

An actual private localhost TLS case composes native storage drivers, synthetic
CryptoKit device custody, registration, invitation access and membership. After
setup, captured paths are lookup → lookup → one uncertain accept → lookup → current.
It checks bearer/field binding, pending/confirmed storage, unchanged account, and
no invitation code in the recovery request or persisted metadata. The server is a
transport fixture, not deployed admission/membership logic or real identity issuance.

See VALIDATION.md for exact results and the still-open intermittent TLS caveats.
Final core **205/205 PASS**,15.797s:
`/private/tmp/pinbook-ios-membership-verified-core.log`.
Final Simulator build-for-testing and unsigned iPhone Release pass:
`/private/tmp/pinbook-ios-membership-verified-test-build.log` and
`/private/tmp/pinbook-ios-membership-verified-release.log`. Compilation only;
no new app-host/UI execution or signed distribution artifact.
Next: localized invitation/join UI and account/session host wiring; explicit
reconciliation/consent for a pending acceptance; owner/team
management; actual provider/client/origin/epoch configuration and physical acceptance.
Complete MLS/media/delivery/recovery/cloud/widget/UX/staging gates remain in
FINAL_UPDATE_CHECKLIST.md. No source push, normal navigation, shared resource,
signing/version or TestFlight change is authorized by this inactive foundation.

The Android/backend task's new source-only `teams/acceptance` contract was inspected
locally (ec8bae6e93a273df9c919099041e2c8ef49f9357). Bounded iOS transport and tests
now exist (TEAM_ONBOARDING_HTTP_IOS.md). The owner now exposes an explicit retry
preparation/confirmation path (TEAM_MEMBERSHIP_RETRY_IOS.md); UI entry is not wired.
It can return exact current membership or an eligible-pending null; null is NOT a
reservation or proof that an older queued accept cannot commit later. A future
retry must keep the same original invitation hash/account/enrollment/team/role,
fresh explicit consent and durable generation, relying on same-identity server
idempotency. Errors are never null. Do not clear PENDING or automatically resend.
The tokenless current-membership recovery implemented here remains distinct.
