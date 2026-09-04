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

## Native screen integration

The membership bridge now accepts a distinct original-invitation entry with the
exact account/team/role and original token supplied again by the caller. The token
is memory-only inside the bridge/owner; screen context contains only identities,
role and a retry flag. No request occurs at construction or appearance.

**Check previous join** invokes the real `prepareRetry` owner. An exact confirmed
result goes directly to Done, without consent or another accept. Eligible pending
shows the original identity/role, a previous-attempt warning and NEW unchecked
consent. Only an explicit enabled **Retry join** can invoke the existing durable
same-identity retry. Code is cleared from the bridge before that attempt, on
confirmed lookup, on tokenless recovery, and on close. An uncertain attempted
retry offers only tokenless Check; retrying again requires a new original-link
presentation. Read-only check failures can be explicitly checked again.

Foreign account/team/role, pending-as-confirmed, and an unexpected confirmed result
from a new-invitation review never enable consent or show success. Close/background
clears details/consent immediately and drains the retained owner's pending work.
Caller cancellation rejects late pending/confirmed outcomes. The parent must still
close/recreate the entire model/bridge on account/session generation changes.

Six new messages are assistant-translated across15 locales plus English. DEBUG
fixtures `retry-pending` and `retry-joined` require the existing ephemeral-fixture
double gate and use no real account, Keychain, network or financial records.
Normal account/workspace routing remains inactive until integration gates pass.

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

- New screen integration: five synthetic-model tests and three real bridge/owner/
  store compositions. Focused **42/42 PASS**. Complete core initially244 tests with
  three unrelated localTLS issues; after a fixture-only atomic port publication
  correction and its regression test, **245/245 PASS** on three bounded full runs:
 20.221s,17.294s,19.769s. Exact evidence and attribution limits in VALIDATION.md.
- Initial physical run: all six membership UI tests PASS, but the catalog test
  still expected306 entries instead of312. Updated its exact count and explicit
  checks for all six new translations. Source/compiled catalog parity already
  passes312 keys. Final rebuilt physical run **272 app +20 UI PASS**,292 total,
  zero failures/skips. UI273.596s; corrected Chinese pending-consent screenshot
  inspected with readable disabled-button text. Result:
  `/private/tmp/Pinbook-QA-Physical-Retry-Final-20260905.xcresult`;
  log: `/private/tmp/pinbook-qa-physical-retry-final-20260905.log`.
  Ordinary unsigned Release PASS:
  `/private/tmp/pinbook-ios-retry-screen-release-20260905.log`.

Invitation/account UI and retained parent workspace routing remain NOT connected.
Owner creation/management, actual provider/client/origin setup, complete physical
custody, MLS/media/delivery/recovery/cloud/widgets and final UX/staging acceptance
remain open. Separate physical QA is owner-authorized; no production identity,
financial data, shared runtime, source push or TestFlight change.
