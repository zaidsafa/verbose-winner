# Invitation account → device → membership ownership

Updated September5,2026. `TeamInvitationDeviceFlow` connects the actual retained
account bridge, device registration owner and membership screen bridge. It is a
core workflow, not yet a normal-navigation SwiftUI host or a live service activation.

## Explicit stages

1. Account screen reviews the invitation and obtains account-access consent or
   explicit continuation with the exact shown existing account. Its output is a
   display-only receipt; it has not registered a device or joined a team.
2. The parent explicitly calls `TeamInvitationDeviceFlow.begin` with that receipt.
   It consumes the account bridge's private intent and completes source cleanup
   before creating the device step. This may read account custody but performs no
   key creation, device HTTP or membership write. Cleanup failure or cancellation
   prevents progression; the committed account is not deleted.
3. Device registration needs its OWN freshly unchecked consent. The flow retains
   the invitation privately and creates `TeamDeviceRegistration` with the exact
   access ticket, not merely an account ID or whichever session is current later.
   Invitation expiry and current account are checked before registration and again
   afterward, including after potentially slow protected reads. Registration still
   checks session/device generations and proof deadlines around every operation.
4. Only a confirmed registration enables explicit `takeMembershipScreen`. Pending
   wait, uncertain transport and recovered absence/retry-ready cannot advance.
   A retry needs new UI consent and uses the existing identity/recovery rules;
   neither this flow nor the registration owner retries automatically.
5. One-use transfer creates a `TeamMembershipScreenBridge` holding the private
   invitation and an exact-account membership owner. Creation performs no lookup,
   acceptance or join write. The child still needs explicit Review and separate
   membership consent. It revalidates account/device/remote registration itself;
   the earlier registration result is not lasting authority.

## Account identity and lifecycle boundaries

`TeamDeviceRegistration.init(account:...)` is now mandatory. The scope-only
initializer was removed; existing source callers were migrated to captured access
tickets. Re-login (even identical IDs/tokens) and pending/completed refresh invalidate
an old owner BEFORE first device preparation. New account access needs a new owner
and new registration consent. Constructing an owner makes no key or session writes.

An account switch during an already-running custody operation is not transactional
rollback: an old-account key may have been created. Its scope never retargets to the
new account, no new-account key is created by that operation, and the post-read
account check prevents further dispatch/success. Existing committed state is kept.
Similarly, an invitation expiring after a device commit prevents advancement but
does not erase the registered device or account. A new valid invitation can reuse
that identity through normal fresh registration lookup.

Close is permanent, cancels the retained registration and drains its actual task.
It clears private invitation ownership and refuses later registration/transfer.
It does not delete account/device metadata. A child already handed off belongs to
the parent workspace: closing this finished device step does not close that child.
The workspace must close the child itself on background/account replacement.

The future native parent must retain and cancel/drain the asynchronous `begin`
task, reject late lifecycle-generation results, and close any discarded returned
flow. Consume the account receipt BEFORE dismissing its source view; disappearance
invalidates an unconsumed receipt. UI state should store only display context, not
`TeamInviteJoinIntent` or account credentials. Context is not authorization.

## Evidence and remaining UI work

- A regression reproduced the old wrong-account registration: both a same-ID
  re-login and a different-account replacement created a key and sent requests.
  Exact-ticket ownership fixes that; tests require zero key/metadata/network writes.
- Additional tests cover refresh invalidation, explicit new-owner/new-consent
  registration, old-scope preservation during a switch, account/device/membership
  consent separation, one-use transfer, expiry, no progress from wait/retry-ready,
  delayed close/caller cancellation, and changed-account membership handoff.
- Actual private localhostTLS composition now uses account screen receipt → device
  flow → membership screen, followed by uncertain acceptance and either tokenless
  recovery or separate original-link retry consent. It checks zero device writes
  before device consent and zero join writes before membership consent. The same
  retained typed client is shared throughout. This uses synthetic account/key/
  server fixtures, not Apple/Google issuance or live encrypted notes delivery.
- Full core, native app-host and build results are in VALIDATION.md. No new native
  device-registration view was added here; account and membership views remain
  independently DEBUG-testable. Next: localized device-registration model/view and
  retained parent navigation with account-generation teardown.

No production identities/capabilities/version, provider clients, shared server or
TestFlight release changed. Keep every FINAL_UPDATE_CHECKLIST.md gate intact.
