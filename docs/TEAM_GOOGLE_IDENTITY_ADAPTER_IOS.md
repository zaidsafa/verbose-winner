# Google native identity adapter — not activated

AppAuth3.0.0 is pinned at `a972daac82d449d58ab119e91c68153e29ddac33` in both
SwiftPM/Xcode lockfiles. The shared core uses AppAuthCore; iPhone presentation uses
AppAuth's system-browser user agent. No provider credentials/configuration or normal
navigation entry point is installed. Personal books, Files backup and build3 stay unchanged.

## Request and credential ownership

- Trusted public configuration requires distinct exact native/server client IDs,
  a provider-profile ID and registered reverse-client callback scheme. No secret,
  project-wide audience wildcard or inferred client allocation. The real adapter
  additionally checks the actual app-bundle scheme before presentation.
- Build the actual SDK request with Google's fixed HTTPS authorization/token
  endpoints, exact raw backend nonce, fresh SDK-generated state and PKCE S256.
  Only openid scope; explicit account selection, online access and no incremental
  scope merge. Server audience and `/oauth2callback` shape follow Google10 source.
- Caller owns an attached foreground scene's presenter; no global key-window
  lookup or silent sign-in at startup. Request a private browser session, which is
  a platform preference, not a guarantee that all browser/provider data is erased.
- Retain the browser session/controller until its callback. Match the exact SDK
  request and state; copy only bounded code/state and a fixed error to the main
  actor. SDK raw response/error/URL/profile objects are not retained there.
- Exchange the code once using a fresh app-owned ephemeral URLSession, form body,
  original verifier/client/redirect and configured audience. Fixed Google endpoint,
  normal TLS, no redirects, ambient credentials, cookies, cache or replacement POST
  stream.15s resource deadline,32KiB actual response cap and existing header bounds.
  Google response policy omits only Pinbook's custom nosniff requirement; no-store,
  JSON, no Set-Cookie/content encoding and all size checks remain. Pinbook auth
  continues to require nosniff. No AppAuth global URLSession override/helper is used.
- Return only the bounded ID token after exact local issuer/audience/presenter/
  nonce and freshness checks. These claims are UNVERIFIED locally: the backend
  still verifies RS256/JWKS, challenge freshness/consumption and account admission.
  Google access/refresh tokens and profile are not saved or returned. No GIDSignIn,
  OIDAuthState persistence, provider restore/refresh, grant revocation or Drive use.
- One pending native attempt. Caller cancellation, expiry, background or scoped
  teardown cancels browser/token work but keeps ownership until terminal callback.
  The HTTP leg waits for native URLSession invalidation. Late/stale responses and
  clock rollback cannot deliver identity. Durable commit still belongs to the
  separate TeamAccountSignInCoordinator and its exact reservation generation.
- Public redirect routing is bounded and restricted to the exact current attempt,
  scheme and path. A consumed URL does not mean sign-in succeeded. AppAuth itself
  parses system-browser callbacks before returning its bounded scalar result to us;
  Pinbook's HTTP/URL limits are not a claim about all internal SDK/browser buffers.

## Evidence and gates

Six intercepted HTTP tests cover exact form encoding/no personal scopes, malformed
configuration/code, claims/header rejection, no retry, response bounds and native
transport cancellation. Four tests use the actual AppAuthCore request/session with
a silent fake user agent: real nonce/state/PKCE construction, matching callback,
foreign URL versus wrong state, duplicate use and cancellation. They open no UI
and make no provider request. Five additional fake-driver iPhone tests cover adapter
ownership/expiry/stale callbacks/redirect scope; runtime results remain separate
from compilation. See VALIDATION.md for exact executed results and failed runs.

Both upstream SDK privacy manifests declare no SDK tracking/collection; source review
confirmed `_APPAUTHTRACE` is disabled by default and it is not enabled by our builds.
That is not a substitute for the app's eventual account-data privacy declarations,
dependency/advisory review or real-device privacy acceptance.

Remaining: confirmed console inventory/clients and redirect registration, exact
live provider claim conformance, approved service origin/profile, UI/localization
and scene teardown, actual system-browser/physical cancellation, account lifecycle,
invited-admission route integration and final release review. Nothing here activates
team admission, membership, shared Infrastructure or personal automatic cloud sync.
