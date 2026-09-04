# iOS invitation account consent — inactive

Updated 2026-09-04. `TeamInvitedSignIn` adds a retained invitation account flow.
It is not linked from normal navigation, and configures no live provider or service.
Signing in is separate from registering a device and joining a team.

## Review and account access

An explicit `preview(code:)` validates a canonical 32-byte base64url code and uses
the public invitation-preview route. It makes no account or financial-data writes.
The returned display contains the team ID, offered role, expiry and the current
account ID if available; it contains no invitation token. Invalid, expired, locked,
pending or wrong-scope local sessions are not treated as a missing account and are
never deleted to make the flow work.

For a new account, the host must show this preview and obtain separate, initially
unchecked account-access consent. `confirmAccountAccess` issues an opaque one-use
confirmation bound to this owner and preview. Reconfirmation invalidates the old
confirmation. A new preview or clear also invalidates it. The confirmation lasts at
most five minutes of wall/monotonic time, clipped to invitation expiry. Rollback is
rejected. Each asynchronous operation additionally has a 125-second budget.

`signIn` consumes the confirmation before starting the durable native login owner.
The exact code, team and role are captured for invited challenge/exchange. Consent,
cancellation and time are checked before/after both transport and native-provider
awaits. The normal native owner retains its own nonce, state, challenge deadline,
durable reservation and exact-generation commit. Failed or uncertain exchange is
not retried and cannot reuse consent or provider proof.

For an existing account, a separate explicit `existingAccountIntent` action reuses
the EXACT current access ticket captured in the displayed preview. It does not
contact Apple/Google or create an account. A refresh, sign-out or re-login invalidates
that ticket, including a replacement with identical account IDs and token values.
A new-account preview cannot overwrite an account created after the preview.

## Exact handoff, not membership authority

The native owner now retains its committed session snapshot internally and exposes
an internal `signInAccess` result. That method rechecks the exact committed generation
and current expiry. It never reloads and returns a different account that happened
to replace the just-committed account. The invitation owner checks it again before
returning `TeamInviteJoinIntent`.

That intent is memory-only and diagnostic-redacted; it carries the invitation code,
team, role, expiry and access-only account ticket. It contains no refresh token.
It is NOT membership permission. The next stage must obtain separate membership
consent, check the current account/device and fresh server registration, durably
record the pending join BEFORE one accept, and reconcile uncertain acceptance using
saved team/enrollment IDs plus `teams/current`. Re-previewing a consumed invitation
is not a recovery mechanism. No device registration or team acceptance is dispatched
by this layer.

## Cancellation and uncertainty

`clear` drops the prepared preview/consent and cancels this owner's pending work.
The unresolved slot remains occupied until non-cooperative work actually settles.
Native cleanup targets only this operation's reservation, never an active or newer
account. Cleanup failure must be reported as uncertainty by the eventual host.
Cancellation after a remote account claim or successful local commit is not rollback.
An admitted account may require a fresh normal sign-in after an uncertain exchange;
do not reuse the old identity proof or silently retry account creation.

The future screen must clear on editing/dismissal/background/session replacement,
and guard late UI results by its own lifecycle generation. Native-provider modal
inactivity is not necessarily backgrounding. Do not store the raw code in saved UI
state, preferences, clipboard, diagnostics or analytics. A cancelled in-flight task
can retain memory until completion; dropping references does not promise secure
memory erasure or screenshot prevention.

Account, device, future join storage and the remote server are separate transactions.
These current-generation checks do not create an atomic transaction across them.
Each next-stage/protected operation must revalidate; a returned snapshot is not
permanent authorization.

## Evidence and open gates

- Eleven synthetic invitation tests cover read-only preview, explicit/single-use
  consent, owner/preview replacement, exact existing-account handoff, account-switch
  races, malformed/public failures, wall/monotonic/rollback expiry, expiry during
  provider UI, uncertain exchange, and cancellation with delayed callbacks.
- Two additional native-owner tests inject a competing replacement immediately
  after the successful login commit, and access expiry immediately after commit.
  Neither returns a stale handoff or erases the committed/replacement account.
- Actual private localhost TLS composition checks preview → invited challenge →
  invited exchange, exact fields, no ambient bearer, no implicit team acceptance,
  no replay and no invitation code saved in synthetic Keychain storage.
- Full core: **177/177 PASS**,16.755s,
  `/private/tmp/pinbook-ios-invitation-full-core.log`.
- Simulator build-for-testing passed; compilation is not app-host execution.
  `/private/tmp/pinbook-ios-invitation-test-build.log`.
- Unsigned iPhone Release build passed:
  `/private/tmp/pinbook-ios-invitation-release.log`. No distribution archive/upload.

Fixtures use synthetic identity and Keychain adapters, not actual Apple/Google
issuance or physical protected storage. The older intermittent localhost TLS issue
remains documented in VALIDATION.md; this passing run does not establish its cause.

Next: bounded durable join-intent storage, separate membership owner/recovery, then
localized invitation/join screens and host lifecycle wiring. Real provider/client
IDs, trusted origin/epoch, physical protection/provider tests, reviewed group crypto,
full delivery/recovery/cloud/widget/UX acceptance and approved staging remain gates.
Keep the complete FINAL_UPDATE_CHECKLIST.md scope and TestFlight build 0.1.0 (3)
unchanged until the final integrated candidate is accepted. No source push, shared
resource, signing, capability, version or TestFlight change occurred here.
