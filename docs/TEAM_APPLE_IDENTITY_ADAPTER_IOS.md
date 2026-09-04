# Apple native identity adapter — not activated

`TeamAppleIdentityAuthorizer` now implements `TeamNativeIdentityAuthorizing` using
AuthenticationServices. It is not instantiated from normal navigation, and no
Apple account, provider capability, client configuration or entitlement was changed.

## Implemented behavior

- Main-actor presentation belongs to a caller-supplied UIWindow in a visible,
  foreground-active scene with a root controller. No global key-window selection.
  Missing presentation fails before allocating a native controller.
- Validate Apple context, exact canonical nonce/state/challenge and remaining time.
  Construct the actual Apple request with the server's raw nonce, independent
  local state, and no name/email scope. Retain controller/delegate/anchor until its
  own callback. No cached credential-state shortcut creates a Pinbook session.
- Only an Apple ID credential with bounded compact-token shape and matching state
  can leave the adapter. Ignore email/name/user/realUserStatus/authorizationCode as
  admission signals. Signature, claims and account admission remain server decisions.
- One pending request. Ownership is assigned before start, including synchronous
  test callbacks. Duplicate or old callbacks cannot complete a newer request.
- Caller cancellation, expiry, app backgrounding and explicit attempt-ID teardown
  request native cancel. Keep the occupied slot until its terminal delegate callback;
  a late success after cancellation cannot return an identity token. Do not cancel
  on every transient inactive scene state, which can occur during native auth UI.
- A final caller-cancellation check handles races with queued main-actor teardown;
  callback-time expiry/clock rollback are rejected. No durable write occurs in this
  adapter. Raw native errors never escape; only fixed error cases are exposed.
- Background observation uses a weak owner and is removed when the adapter releases.
  Deadline work is cancelled on completion. Explicit view/scene teardown should
  call `cancelAuthorization(attemptID:)` for that exact request.

The installed iOS26.5 SDK's `ASAuthorizationController.h` documents that cancel
(iOS16+) completes through the delegate, and that the controller is retained until
the flow completes/cancels and its callback is made. This implementation targets
iOS26.1 for the app (the shared package declares iOS17+), so it needs no older-OS
cancellation fallback. The credential header states
that credential.state echoes request.state. This is API/source evidence, not proof
of a real Apple account interaction on hardware.

## Tests and acceptance boundary

Six iPhone app-host tests are implemented using a DEBUG-only injected fake driver
and hidden, unattached windows. They cover exact request fields/no scopes,
synchronous completion, pre-cancellation/missing presentation, state/type/token
rejection, clock rollback, cancellation-ignoring driver, expiry cancellation and
old callback/lifecycle isolation. They never call the real driver's start method,
show an Apple sign-in sheet, or contact Apple. See `VALIDATION.md` for executed
results; compilation alone is not a passing runtime test.

Still required: actual sign-in UI wiring and scene teardown, Apple capability/client
setup, real provider/backend acceptance, accessibility/localization and physical
presentation/cancellation verification. Team features remain disabled in normal
navigation. Existing TestFlight build3 and personal data remain unchanged.
