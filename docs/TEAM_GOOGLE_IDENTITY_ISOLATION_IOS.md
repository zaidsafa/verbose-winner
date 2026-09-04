# Google identity integration review — not activated

Reviewed 2026-09-04. Apple+Google provider direction is accepted. No Google SDK,
client ID, URL scheme or account has been installed/connected by this review.
Normal navigation and personal Files backup are unchanged.

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

## Integration decisions still needed

- If adopting GIDSignIn, reserve its entire singleton state for TEAM identity;
  future personal Drive must use a distinct authorization owner, client flow and
  credential namespace. Never infer separation merely from requesting fewer scopes.
- Retain one global SDK request owner. Cancellation/expiry must reject late results
  and quarantine ownership until the SDK's terminal callback, without claiming that
  the underlying browser was cancelled. Never use private SDK cancellation APIs.
- Define provider-token cleanup and error handling explicitly. A void signOut call
  is not evidence that Keychain deletion succeeded; Pinbook account-session custody
  remains a separate passcode-required store, never a copy of the SDK auth state.
- An AppAuth-owned system session is the alternative if reliable cancellation and
  volatile-only provider token custody are required. Verify native/server audience,
  raw nonce, state, PKCE and fresh selection against the backend's exact profile;
  do not invent an audience or accept cached identity to make an adapter work.
- Validate trusted public client IDs and registered reverse-client redirect scheme
  before SDK invocation. Inspect actual console inventory before creating duplicate
  clients. Android source currently contains no committed live team client IDs;
  historical project references are not verified iOS/team configuration.
- UI consent, scene teardown, redirect ownership, real issued claims/server
  admission, privacy manifest review and physical cancellation remain gates.

No provider-choice question needs to be asked again. Public console identifiers
and approved service configuration still require confirmed inventory before use.
