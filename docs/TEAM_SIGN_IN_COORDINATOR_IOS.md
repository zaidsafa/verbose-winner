# Native sign-in ownership — inactive integration

This connects trusted configuration, a native-authorizer protocol, the six-route
HTTP adapter and protected custody. It is not yet a complete user-facing sign-in:
concrete Apple/Google adapters, client configuration, presentation/lifecycle UI and
live provider/service acceptance remain open. Construction does not connect.

## Durable reservation, not a fabricated account

- Explicit consent first. `beginLogin` reserves the empty fixed session slot with
  a random generation, trusted origin/provider scope, creation time and120s expiry.
  The marker contains no account identifier, ID token, access or refresh token.
- Add-only semantics preserve an existing active session, refresh barrier or login
  reservation. They are never silently replaced by another login. Account switching
  requires explicit prior local sign-out; notes and recovery keys are untouched.
- Only `completeLogin` can install the server-issued pair through a generation-
  matched update. There is no add-on-missing fallback. The older unbound initial-save
  function is now internal fixture seeding only, not a public login installation API.
- `cancelLogin` removes only the exact reservation. An old callback cannot remove
  a newer reservation or install over it, nor recreate a session after cancellation.
- On restart, a saved reservation yields loginPending, never usable credentials.
  Explicit abandon/retry removes the current reservation by generation. Read or
  write failure is not interpreted as absence or rollback. Ambiguous final commit
  is either the reservation or the entire new pair; no second automatic exchange.
- Same new passcode-only/non-backup session service; no archive-key class changes.
- Explicit local sign-out reads the session-or-reservation record once and deletes
  that exact generation. If a concurrent login commits, deletion fails stale; it
  cannot falsely report success by rereading only the now-missing reservation.

## One-owner flow

`TeamAccountSignInCoordinator` reserves first, requests a fresh server challenge,
constructs the native request context, awaits the request's own provider callback,
validates provider kind/state/bounded token shape, exchanges once, then commits to
the matching reservation. Only the server verifies OIDC signature/claims/admission.

The public initializer constructs HTTP from the same trusted origin used by
custody. Provider profile comes from trusted scope, not token claims. Provider
adapter must forward the exact nonce and own its request/cancellation callback;
cached SDK currentUser or personal Drive tokens are not fresh login proof.

At each asynchronous boundary, recheck cancellation, operation ownership, stored
generation and time AFTER protected-store reads. Both wall and ContinuousClock
deadlines apply; wall rollback, whole-attempt120s exhaustion, and the individual
challenge's earlier monotonic deadline fail closed. Callback state/type mismatch
cannot proceed to exchange. No local account identity is inferred from token text.

Cancellation keeps the occupied operation slot until a cancellation-ignoring
provider/transport actually settles. The late callback is discarded. Explicit
owner cancellation also removes its reservation; caller-task cancellation or
failure may leave the durable marker for explicit abandon/retry. No new provider
request starts behind an unresolved callback. Native SDK adapters still need to
implement their own session/controller cancellation and callback quarantine.

After atomic commit there is no new await/cancellation-as-rollback check. Sanitized
provider/transport failures never expose raw SDK errors or credential payloads.
Session/local sign-out is not remote revocation, account deletion or team authority.

## Verification

- Seven new tests: reservation contents/late generation; complete successful flow;
  consent/existing-session/pre-cancelled no-contact; cancellation-ignoring native
  callback; cancelled exchange/new-owner reservation; wall/elapsed/state/provider
  rejection; before/after-commit ambiguity with one exchange.
- Real localhost TLS test connects challenge→synthetic native identity→exchange→
  reservation commit with exact request routes/fields. This is NOT real Apple/Google
  issuance or backend OIDC verification. Those remain separate acceptance gates.
- Actual Simulator SecItem test now includes reservation creation/read/commit,
  stale cancellation rejection and subsequent rotation. It uses an isolated DEBUG
  service/WhenUnlocked class, not physical passcode-only proof.
- Final core103/103, app-host124 passes plus one hardware file-protection skip,
  unsigned Release and Simulator compilation passed. See `VALIDATION.md` for
  exact logs, result bundle and the corrected test-fixture cleanup stall.

Next: real native controller/SDK adapters and presentation ownership, explicit
abandon/switch UX, approved provider IDs/redirects/capabilities, server review access,
scope/Drive isolation, physical and staging acceptance. No normal navigation
activation, source push or TestFlight upload in this checkpoint.
