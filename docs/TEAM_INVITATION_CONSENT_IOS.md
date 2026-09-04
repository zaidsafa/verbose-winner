# iOS invitation account consent — inactive

Updated 2026-09-05. `TeamInvitedSignIn` adds a retained invitation account flow.
It is not linked from normal navigation, and configures no live provider or service.
Signing in is separate from registering a device and joining a team.

## Account screen and lifecycle bridge

`TeamInvitationAccountScreenBridge` now retains that real owner for one screen.
Construction does no I/O. Explicit Review returns only team, role, expiry, shown
account ID and an opaque preview ID. The original code stays privately in memory.
New-account access requires freshly unchecked consent; an existing account has
a separate explicit continuation and never asks for new-account consent. Exact
preview identity and all displayed fields must match. Access consumes the code
and prepared screen handle before one attempt; uncertain access cannot be replayed
or silently re-previewed in the same presentation.

Completion returns an opaque display-only receipt, NOT the secret join intent.
Only the retained bridge holds that intent. A parent can call `takeIntent` once
with the exact receipt; the owner rechecks invitation expiry and the exact current
account generation before handoff. A changed/expired account consumes the receipt
without returning the intent or deleting any account. This recheck is not an
atomic lease: the next device/membership owner must still revalidate scope and
obtain its own explicit consent. No device or membership request is made here.

Close is permanent and idempotent. It drops screen handles/code/intent, cancels
only its own operation, awaits owner cleanup AND the real pending work, and reports
cleanup failure. The observable model clears its UI immediately, rejects late
results by generation, retains cleanup work even when its presentation task is
cancelled, and exposes cleanup uncertainty without restoring consent. Never share
one bridge/owner between presentations. Host must close/recreate on code edits or
session-generation replacement, and must consume the handoff before dismissing
the source screen; disappearance invalidates an unconsumed receipt.

`TeamInvitationAccountView` is a native preflight modal with readable identity/role
cards, initially unchecked consent, explicit existing-account action, simple
progress/uncertainty and Reduce Motion-aware transitions. It clears on actual
background/disappearance, not provider-modal inactivity. Eleven new messages have
assistant-authored translations in all15 non-English catalogs; native linguistic
review remains open. It is not a branded Apple/Google button or live provider demo.
Its DEBUG host requires both ephemeral fixture mode and the invitation-account
flag; only `new`, `existing`, `uncertain` scenarios are accepted. That host has no
Keychain/provider/network/financial write. Its Done action intentionally closes
the isolated test screen; parent progression is NOT wired into ordinary navigation.

Nine model and six real bridge/owner/session tests cover no automatic I/O, exact
displayed-account access, consent, one-use receipt/intent, forged handles, changed
account/expiry, cleanup, late results and no exchange replay. Focused25/25 PASS
before the additional post-Keychain expiry regression; final full core261/261 PASS.
The handoff samples time/cancellation again after protected account reads, rejecting
access expiry, invitation expiry and rollback during that read. See VALIDATION.md
for the red/green regression and native build/test evidence.

Next: parent account/device/membership workspace and explicit device-registration
screen, account-generation teardown, then owner invitations. Before UI wiring,
registration must accept the exact displayed handoff ticket: its current
`register(consent:)` loads whichever account is current at dispatch. Checking a
returned result only afterward cannot prevent key creation for a switched account.
Pin/check the expected ticket BEFORE the first custody prepare/write, then retain
the existing before/after-operation checks. Android's owner-side
contract is `docs/TEAM_ANDROID_INVITATION_UI.md` at a3af32e (partner report): keep
fresh unchecked issuance consent and explicit bounded one-use native sharing;
it is not a recipient-account contract or proof of actual server delivery.

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

The September4 checkpoint above predates the durable membership and screen work
described at the top. Next remains parent/device integration. Real provider/client
IDs, trusted origin/epoch, physical protection/provider tests, reviewed group crypto,
full delivery/recovery/cloud/widget/UX acceptance and approved staging remain gates.
Keep the complete FINAL_UPDATE_CHECKLIST.md scope and TestFlight build 0.1.0 (3)
unchanged until the final integrated candidate is accepted. No source push, shared
resource, signing, capability, version or TestFlight change occurred here.
