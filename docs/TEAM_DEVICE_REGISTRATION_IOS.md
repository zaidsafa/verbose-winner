# iOS account-bound device registration — inactive

Updated 2026-09-05. `TeamDeviceRegistration` composes protected account custody,
device custody and the retained typed onboarding HTTP client. There is no normal-
navigation entry point, real provider/origin/epoch configuration or automatic work.

## Current session and cancellation

The owner now REQUIRES the exact reviewed `TeamAccountAccessTicket` at initialization;
the old scope-only initializer is removed. It never captures a different current
account at Register time. Re-login/refresh invalidates that owner before the first
device prepare/write, even when identifiers and credentials are reused. Construct
a new owner and obtain new consent after account/session replacement. The retained
invitation/device connector passes the account bridge's exact ticket by construction.
See TEAM_INVITATION_DEVICE_FLOW_IOS.md and the latest VALIDATION.md checkpoint.

`TeamAccountAccessTicket` carries only the access credential, exact account/session,
scope, expiry, observed time and local generation. It contains no refresh token.
The account store creates it only from active unexpired custody; `requireCurrentAccess`
re-reads the exact protected record and compares every captured identity/credential/
expiry/generation field. Refresh pending, sign-out or re-login invalidates the old
ticket, even if account/session IDs and credentials are reused. It is not portable.

Registration HTTP overloads use that access-only ticket. Existing snapshot wrappers
remain compatible and immediately derive a ticket; unrelated invitation methods keep
their existing additional response checks. The same retained `TeamAuthHTTPClient`
must be injected into authentication and registration owners to share its unresolved
native IO slot. Constructing separate clients would not create a global lock.

One registration owner is retained while a child operation is unresolved. Caller or
lifecycle cancellation invalidates it and cancels the child without releasing busy
ownership early. The custody driver runs protected storage/key operations in an awaited
detached task, propagates cancellation and waits for actual completion. A slow native
operation is not killed or assumed rolled back. A canceled write may have committed.

The owner checks both wall and continuous time, with a125second operation lifetime at
checkpoints. The received challenge has an additional monotonic deadline clipped to its
absolute expiry. Checks surround custody/network work, including before proof dispatch
and after completion/metadata persistence. These are checkpoint limits, not a guarantee
that an uncooperative OS/transport call returns within125seconds. Device-generation reads
are followed by fresh account-custody checks, then time/cancellation are sampled again.

## Flow and recovery

1. Revalidate the retained exact access ticket before any device-key creation. Explicit registration
   consent is required. Construct device scope only from trusted origin/epoch and
   that account, then prepare/reopen the same protected identity.
2. Always perform a fresh exact-key lookup, including for local REGISTERED metadata.
   READY plus a late matching server commit adopts its registration without another
   challenge/signature. A registered key missing remotely is unavailable, not a
   reason to replace its identity or silently create another registration.
3. READY plus explicit null requests a new bound challenge, commits the pending
   attempt before signing, rechecks current session/device/time, and sends one proof.
   Match the exact response, persist metadata and recheck before reporting success.
4. SUBMIT_PENDING/RECOVERING before its prior deadline returns a wait state without
   HTTP. Afterward, persist a fresh recovery generation, then perform a fresh lookup.
   Matching registration confirms; explicit null returns RetryReady with the SAME
   key/device. No automatic new challenge, proof or retry occurs in that attempt.
5. Errors never become null. Lost or late completion leaves uncertainty. A deadline
   does not establish server time or noncommit; stable identity and server uniqueness
   remain required. An explicit new attempt reconciles instead of replaying proof.

Account and device records are separate transactions. A concurrent sign-out may leave
registered metadata on disk, but final validation refuses a successful account-bound
flow. Metadata is not team membership, current access, attestation or a replacement for
fresh authorization. Local sign-out does not imply remote revocation/deletion.

## Evidence and next stage

Thirteen new core tests cover access-ticket expiry/forgery/refresh/re-login; ordinary and
repeat registration; late-commit adoption; unresolved wait/fresh recovery/null; registered
absence; foreign responses; sign-out during every network stage, key read/signing and
metadata commit; stale device generations; wall/monotonic/signing deadlines; retained
ownership for canceled uncooperative completion; and no keys without a usable account.

A composed actual localhostTLS test verifies lookup→challenge→complete→fresh lookup,
scoped bearer use, captured raw64 P256 signature, durable registration and unchanged
account custody. It uses synthetic in-memory Keychain APIs and CryptoKit fixture keys,
not Secure Enclave hardware or the real registration service.

An initial full run hit one older TLS sign-in transport failure; its precise cause was
not captured and is NOT claimed fixed. The isolated case passed. Test-only bounded
route/error diagnostics and three mandatory fresh-listener/certificate cases were added;
every case must pass, with no request/credential replay or retry-on-failure. Subsequent
full passes and exact logs are in VALIDATION.md. Preserve this intermittent-test caveat
for final regression; new provider/hardware/UI evidence is still absent.

Final full core **163/163 PASS**,13.498s:
`/private/tmp/pinbook-ios-registration-owner-final-core.log`.
Final Simulator build-for-testing **PASS**:
`/private/tmp/pinbook-ios-registration-owner-final-test-build.log`.
Unsigned iPhone Release **PASS**:
`/private/tmp/pinbook-ios-registration-owner-release.log`.

The older evidence above predates the account screen and connected device flow.
Next: device-registration consent UI and full retained native parent navigation.
Separate membership consent plus durable team/enrollment/role/invite-hash intent
before accept now exists. Read Android TEAM_ANDROID_INVITATION_CONSENT.md and TEAM_ANDROID_JOIN_RECOVERY.md:
unknown acceptance/process death must recover through persisted IDs and teams/current,
not re-previewing a consumed invitation. No raw invitation token should be persisted.
Actual membership authority, retired-device/epoch cleanup, UI/lifecycle, provider setup,
MLS, full encrypted delivery and final acceptance remain required. No shared resource,
phone, source push, signing/version or TestFlight change.
