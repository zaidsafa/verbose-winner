# Native account transport — inactive implementation

The iOS adapter implements Android-owned contract `TEAM_AUTH_HTTP_V1.md` at
`15751a7` (peer subsequently tested its adapter at `dcc3b776`). No production origin, provider ID, credentials, listener or activation
has been invented. Constructing `TeamAuthHTTPClient` does not connect; normal app
navigation does not instantiate it. This is not a user-facing sign-in/session flow.

## Request and response rules

- Caller supplies a trusted HTTPS origin only: no user/password, query, fragment
  or path prefix. Six fixed `/api/v1/auth/` routes; exact field names and scoped
  bearer authorization. ID tokens and refresh tokens stay in POST JSON bodies,
  never URL/query fields. Request bodies are capped at20000bytes.
- Each operation creates an ephemeral URLSession with no cookie, URL cache or
  credential storage; cookies are disabled on configuration and request. Normal
  platform server-trust validation remains enabled. Other authentication challenges
  are cancelled, without supplying Basic/Digest/proxy/client-certificate credentials.
- Redirects are refused rather than forwarding an auth body/header to another URL.
  Request timeout10s/resource timeout15s are configured. Private localhost TLS
  acceptance is recorded below; approved staging/provider/device acceptance is open.
- Application response accumulation is limited to32KiB, including when the sender
  omits Content-Length. Oversized declared or actual bodies cancel. This bounds our
  buffer, not all opaque Foundation/network-stack/header allocations. Headers are
  also checked after receipt (32fields/8192text bytes). No cookies or content encoding;
  JSON MIME type, no-store and nosniff are required. Invalid metadata fails closed.
- UTF8/no BOM, exact top-level fields, types, canonical43-character32-byte credentials,
  JS-safe integer times and related expiry ordering. No error/provider body is
  returned to the UI. Fixed error codes must match their documented HTTP status.
  JSONSerialization supplies standard duplicate-key semantics; no custom JSON or
  JWT cryptography is introduced. A parsed pair is not a current-expiry decision.
- Refresh replies must preserve account/family/absolute expiry and rotate both
  tokens, with each new token different from BOTH old tokens. Session replies must
  match the supplied pair's account/family. No identity
  switching or local archive mutation occurs on an error.
- The adapter contains no application retry loop. Cancellation and delegate races
  resume once; cancellation after a remote commit does not imply rollback. No claim
  of exactly-once delivery by URLSession or the network. Context/pair public diagnostic
  descriptions/reflection are redacted; Swift copies are not securely erasable.
- POST uses one initial InputStream and refuses both replacement-body-stream
  delegate callbacks. This prevents furnishing a fresh credential body for a
  recoverable retry. [Apple describes when replacement streams are requested](https://developer.apple.com/documentation/foundation/urlsessiontaskdelegate/urlsession(_:task:neednewbodystream:)).
  This is not universal exactly-once delivery; the durable refresh marker remains
  mandatory even after the private TLS request-count tests pass.

## Mandatory next integration

This is a low-level transport, not safe session orchestration by itself. Before
calling refresh, the session coordinator must serialize it and durably store a
non-backup in-flight/uncertain marker. Atomically replace both returned credentials
and clear the marker before releasing waiting work. Process death, unknown outcome
or protected-store failure requires reauthentication, never blind replay of the old
refresh token. Do not erase saved notes, assume rollback or identify an account as
deleted from a sign-in failure. Validate current expiry/clock and account-selection
consent before using or retaining returned credentials.

Still required: separate non-backup protected session storage, native controller/SDK flow,
real provider clients and approved HTTPS origin, current restore authority, invite/
account deletion, enrollment/roles, group encryption and live delivery integration.
No session credential belongs in recovery-key custody or a portable backup.
For new session custody, WhenPasscodeSetThisDeviceOnly is the intended policy:
passcode required, unlocked-only, no backup or synchronization. Passcode removal
may invalidate sessions and require sign-in. Existing archive recovery keys stay
WhenUnlockedThisDeviceOnly, avoiding a destructive key migration. "ThisDeviceOnly"
alone does not mean no backup: same-device restore is possible. See
[Apple's accessibility guidance](https://developer.apple.com/documentation/security/restricting-keychain-item-accessibility)
and [Platform Security](https://support.apple.com/en-ie/guide/security/secb0694df1a/1/web/1).

## Evidence

Eight URLProtocol-intercepted URLSession/codec tests cover all six route methods/
fields, cookies/bearer scoping, unsafe origins, auth-challenge policy, redaction,
types/unknown fields/BOM/UTF8/times, exact/over response bounds without length,
redirect refusal, fixed errors, refresh identity/family/expiry/token mismatch and
early/in-flight cancellation with request counts proving no application retry.
The isolated protocol handles all requests so no test falls through to DNS/network.

Initial core77/77 passed: `/private/tmp/pinbook-ios-auth-http-tests.log` (intercepted
transport only). Then four macOS-package tests exercised real Foundation/CFNetwork
against a private localhost TLS listener. Each fixture generates a one-day public
test certificate/key in a private temporary directory and removes it afterward.
DEBUG-only internal localhost anchor injection still evaluates hostname, dates,
EKU and chain with SecTrust; never alters system trust. Public construction has no
anchor override; Release rejects it. Default untrusted TLS is rejected before HTTP.

Actual POST fields, one attempt/body for503 Retry-After:0,408 and lost response
after body read, redirect refusal, fixed/chunked overflow, cancellation and stalled
body timeout passed4/4 in11.990s. Initial fixture failed because its certificate
lacked serverAuth EKU; corrected the fixture, not platform validation. Temporary
diagnostic logging was removed. Final full core81/81 passed in12.165s at
`/private/tmp/pinbook-ios-auth-tls-full-core.log`; unsigned iPhone Release and
Simulator test compilation also passed. macOS loopback evidence is NOT iOS device
TLS/provider/deployed-API/secure-storage acceptance. See `VALIDATION.md`.
No source push or TestFlight update.
