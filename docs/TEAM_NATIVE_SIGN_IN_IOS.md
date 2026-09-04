# Native sign-in request binding — inactive implementation

Apple+Google are the accepted implementation direction. This slice implements
fresh local callback binding, not a connected account, live provider login or team
authorization. No client IDs, entitlement changes, SDK dependency or HTTP route
has been invented. `TeamNativeSignIn.swift` is compiled in core and iOS.

## Implemented contract

- One volatile attempt at a time. Host supplies its trusted selected provider and
  profile ID plus the backend's fresh challengeID/nonce/expiry. Challenge and nonce
  must be canonical 32-byte, 43-character unpadded base64url. Local expiry is
  checked against JS-safe Unix milliseconds and the current two-minute profile.
- A separate cryptographically random256-bit local state is generated per attempt.
  Apple request construction uses exact raw nonce/state and requests no name/email
  scope; exact issuer+subject backend admission does not need profile data.
- Apple callback must echo the same state. Google SDK callback is bound by its
  attempt UUID; the SDK owns OAuth state/PKCE. Call only from that fresh interactive
  request, never `currentUser`, cached restore or an unrelated token-refresh callback.
- A matching callback is consumed once, even when malformed, cancelled, expired or
  wrong-provider. Old cancellation/callback IDs cannot consume a newer attempt.
  Detected wall-clock rollback drops the pending attempt. Start a new challenge
  after recovery; do not pretend the expired/consumed challenge can be retried.
- Token input is bounded to16KiB and checked only for compact ASCII shape. It is
  explicitly **unverified**. Only the backend validates signature, issuer, audience,
  presenter, nonce, token time and admitted account before issuing a session.
- Context/submission descriptions and reflection are redacted. Neither is Codable
  or persisted. This does not guarantee physical erasure of Swift String copies.
  No tokens/state/nonce/profile identifiers in diagnostics, analytics or backups.

## Integration still required

Retained native authorization controller and presentation anchor, system callback
and cancellation handling, exact Apple capability/client setup, Google pinned SDK
and configuration, trusted TLS challenge/exchange routes and bounded failures.
Provider authorization can legitimately make the app inactive; do not copy the
recovery-key screen's blanket inactive-clear rule into this sign-in flow. Bind the
system callback, expiration and explicit dismissal to its own attempt instead.

Sign-in sessions need device-only atomic custody, durable pre-dispatch refresh
markers, single-flight refresh and logout/account revocation. Ambiguous refresh
or persistence failure requires reauthentication, not retry of a spent token.
Team/device enrollment, roles, encryption and Infrastructure restore-safe authority
remain separate gates. Personal Drive consent is unchanged and not requested here.

## Evidence boundary

Seven synthetic tests cover fresh state/raw nonce, redaction, single consumption,
overlap, stale cancellation/callbacks, wrong state/provider, expiry/clock rollback,
malformed challenges and token bounds. Native Apple request construction is tested
without presenting a provider UI or using any real account. Core suite69/69 passed:
`/private/tmp/pinbook-ios-native-signin-final-core.log`. Source checkpoint3b02975
also passed108 app/UI tests plus one explicit hardware skip and unsigned iPhone
Release compilation. Details are in VALIDATION.md; no live Apple/Google claim
compatibility or session transport is established yet.

Provider API/source assessment: `TEAM_AUTH_MLS_FEASIBILITY_20260904.md`.
Backend-owned session semantics: peer `docs/TEAM_ACCOUNT_SESSIONS.md` in
`/Users/zaidsmac/Documents/ChatGPT/TC Projects/pinbook-team-delivery`.
