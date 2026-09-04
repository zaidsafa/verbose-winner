# Google identity integration review — not activated

Reviewed 2026-09-04. Apple+Google provider direction is accepted. The implementation
now uses exact AppAuth3.0.0 for system-browser request/state/PKCE, plus Pinbook-owned
bounded token HTTP. This supersedes the earlier undecided SDK note. No GIDSignIn,
real client ID, URL scheme or account has been installed/connected. Normal
navigation and personal Files backup are unchanged. See TEAM_GOOGLE_IDENTITY_ADAPTER_IOS.md.

## Verified SDK boundaries

The official [10.0.0 release](https://github.com/google/GoogleSignIn-iOS/releases/tag/10.0.0)
updates AppAuth/GTMAppAuth major dependencies and platform minimums. Its
[package manifest](https://raw.githubusercontent.com/google/GoogleSignIn-iOS/10.0.0/Package.swift)
declares AppAuth3, GTMAppAuth6 and iOS15 minimum. Those minimums alone do not prove
our full build/regression compatibility; no dependency adoption is claimed.

The [public header](https://raw.githubusercontent.com/google/GoogleSignIn-iOS/10.0.0/GoogleSignIn/Sources/Public/GoogleSignIn/GIDSignIn.h)
exposes fresh interactive sign-in with a custom nonce and replacement of SDK-saved
state. Cached restore is not a fresh Pinbook challenge response. The public API
does not expose native authorization-flow cancellation; signOut is not cancel.
disconnect revokes OAuth grants and must not implement local team sign-out.

The [implementation](https://raw.githubusercontent.com/google/GoogleSignIn-iOS/10.0.0/GoogleSignIn/Sources/GIDSignIn.m)
uses one shared instance and an SDK-owned Keychain item named auth. signOut removes
that SDK session but discards its deletion error. Missing client/presenter/URL-scheme
configuration can raise an Objective-C exception, not a catchable Swift Error.
The interactive request forwards the explicit nonce and configured server audience
through AppAuth. This is source evidence, not real provider claim acceptance.

## Why the implementation uses AppAuth rather than shared GIDSignIn state

- AppAuth's external-user-agent session exposes cancellation and can remain a
  volatile request. We do not construct/persist OIDAuthState or use a cached identity.
- AppAuth's token helper uses a process-global URLSession provider (sharedSession
  by default), without returning a per-request cancellation handle. Pinbook instead
  uses its own bounded ephemeral exchange; no global session override is made.
- A single native owner keeps browser/token work occupied until actual completion.
  Cancellation/expiry rejects late identity results. No private SDK API, signOut
  or disconnect is needed to clean up a saved Google session, because none is saved.
- Future personal Drive still requires a distinct authorization flow, consent and
  credential namespace. No Drive scope is requested by team login. Pinbook's own
  account-session custody remains its separate passcode-required Keychain store.

## Remaining activation gates

- Verify real native/server audience and authorized-presenter behavior against the
  backend's exact profile. Current source follows the official SDK's audience
  parameter in authorization and token requests and reverse-client callback path;
  synthetic tests do not establish Google-issued claim compatibility.
- Validate trusted public client IDs and registered reverse-client redirect scheme
  before SDK invocation. Inspect actual console inventory before creating duplicate
  clients. Android source currently contains no committed live team client IDs;
  historical project references are not verified iOS/team configuration.
- UI consent, scene teardown, redirect ownership, real issued claims/server
  admission, privacy manifest review and physical cancellation remain gates.

No provider-choice question needs to be asked again. Public console identifiers
and approved service configuration still require confirmed inventory before use.
