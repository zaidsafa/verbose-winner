# Explicit original-invitation retry — inactive

Updated 2026-09-05. This extends the existing membership owner and join store.
It does not enable normal team navigation or silently retry an uncertain request.

## Separate check, consent and attempt

`prepareRetry(token:teamID:role:)` requires the ORIGINAL token supplied again by
the caller; it is not persisted. The owner remains bound to one exact current
access-only account ticket and trusted origin/authority epoch. It loads the current
registered device, then a PENDING record with the same account/team/role and
domain-separated invitation hash. Enrollment must still match the original.

After a fresh registration lookup, `beginRecovery` durably rotates the record
generation BEFORE one `teams/acceptance` read. Current session/device checks follow
slow storage/network operations. Any local/HTTP error preserves uncertainty and
does not arm consent, erase PENDING or send `teams/accept`.

- Exact current membership is confirmed against that generation and returned as
  `joined`; no accept request occurs. An expired/consumed original invitation can
  still reconcile server-confirmed membership. A new public invitation preview is
  not required by this recovery entry.
- Explicit successful null means eligible pending at the serialized server check,
  NOT proof that an older queued accept cannot later commit. The owner rechecks
  current metadata and returns a fresh opaque `ready` presentation only.
- The UI must display the original account/team/role and previous-attempt warning,
  with NEW initially unchecked consent. Calling `join` without consent sends nothing.
  Calling with consent consumes that exact presentation before any attempted work.
- Join rechecks the current account/device, fresh registration and exact recovery
  generation. `beginExplicitRetry` rotates a durable PENDING generation before ONE
  accept using the same original token/team/enrollment/role. Same-identity server
  idempotency, not local null, handles any late prior commit. Confirmation remains
  exact and generation-bound. Unknown response leaves the retry marker recoverable.

The new consent expires after at most five minutes, clipped to current account
expiry. This is a local consent deadline, not an invented invitation expiry.
Server-side eligibility/expiry is checked again on accept. The retained owner also
enforces its existing monotonic access lifetime and125-second operation deadline.
Check membership, new preparation, cancellation or close clears old consent.
Close drains actual unresolved work; canceled/late callbacks cannot return success.

## Durable storage behavior

`retryCandidate` is read-only. `beginExplicitRetry` requires a current PENDING
snapshot, original hash, same enrollment/account/epoch, valid registration shape
and explicit consent. It preserves scope/team/enrollment/role/hash/phase and changes
only generation/checked time. Existing CAS/index bounds and protection are unchanged.
No schema change, raw token, financial record, archive key or remote authority is
introduced. A competing recovery/retry invalidates an earlier generation.

Consent time is checked before and after native commit and the final reread. A
late/uncertain write may have committed, but cannot return dispatch permission.
The owner must still perform current account/device and monotonic checks around
this synchronous IO; local metadata is not a separate authorization source.

## Evidence and remaining work

- Five new store cases; focused store **17/17 PASS**,1.069s.
- Nine new owner cases; focused owner **25/25 PASS**,0.075s.
- Full core **236/236 PASS**,16.539s:
  `/private/tmp/pinbook-ios-explicit-retry-full-core.log`.
- Simulator build-for-testing and unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-explicit-retry-test-build.log` and
  `/private/tmp/pinbook-ios-explicit-retry-release.log`. Compilation, not execution.
- Actual private localhostTLS composition now covers both tokenless current-team
  recovery and separately confirmed retry after an uncertain first accept. It
  checks one accept before new consent, two identical accept bodies only after
  fresh consent, durable marker counts, exact bearer and no saved raw invitation.
  This is a synthetic transport fixture, NOT deployed backend/DB eligibility proof.
- Initial store-test compilation failed on throwing assertions; corrected only
  the tests. Exact logs and native build results are in VALIDATION.md.

Retry screen/bridge entry, invitation/account UI and retained workspace routing are
still NOT connected. The existing membership modal only exposes new-join and
tokenless recovery. Owner creation/management, actual provider/client/origin setup,
physical custody, MLS/media/delivery/recovery/cloud/widgets and final UX/staging
acceptance remain open. Previous intermittentTLS failures remain unproven/unfixed
despite this passing run. No cross-task message, shared resource, physical install,
source push, signing/version change or TestFlight update.
