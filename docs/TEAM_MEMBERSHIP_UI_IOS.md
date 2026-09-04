# iOS membership screen — inactive integration surface

Updated 2026-09-04. This adds a native, localized membership confirmation and
tokenless recovery screen. It does not enable team navigation or a live service.

## Presentation and lifecycle

`TeamMembershipScreenModel` owns only UI state and opaque presentation handles.
`TeamMembershipScreenBridge` retains the memory-only invitation and one existing
`TeamMembershipJoin` owner. The host must create a new bridge/model per presentation
and close it when its exact account/session changes. No request occurs at init or
on appearance; no raw invitation, bearer, persistence or raw error is in UI state.

1. **Review invitation** calls the real read-only owner and shows its exact team,
   account and offered role. Identifiers are verbatim, monospaced, left-to-right,
   wrapping and privacy-sensitive; role and labels are localized.
2. Consent starts unchecked. **Join team** remains disabled until checked; the
   model consumes that preview and clears consent before dispatch. The owner still
   enforces its exact opaque preview, deadlines, current account/device and durable
   PENDING-before-accept policy. No automatic or second join is exposed.
3. An uncertain join offers **Check membership**, not another join. Reopening an
   invitation with existing pending/confirmed metadata also offers that tokenless
   check, rather than an endless read-only review failure loop. Saved-team entry
   exposes only Check. Errors preserve uncertainty; only an exact confirmed
   account/team/role and revision can show success.
4. Close/background immediately clears displayed details and consent, cancels the
   operation and rejects late results by generation. Separate cleanup waits for
   both the service's close and actual pending task completion. The parent must
   await cleanup before releasing/reusing its shared workspace resources.

The screen explains that joining does not share existing private notes and that
shared-note delivery is not enabled. Native glass buttons, semantic text colors,
theme surfaces, a scrollable 560-point maximum content width, wrapping text and
Reduce Motion-aware transitions reuse the app's design. No cropped screenshot or
compiled source is evidence of live accessibility/contrast acceptance.

## Test-only host and evidence

DEBUG presentation requires BOTH an ephemeral `-PinbookFixture` and explicit
`-PinbookTeamMembership`. Whitelisted `-PinbookMembershipScenario` values are
`success`, `uncertain`, `recovery`. These actors use public synthetic values only,
with no Keychain, network, provider, account or financial mutation. Release excludes
the fixture host and remains on normal `AppShellView` navigation.

- Nine core screen tests cover separate unchecked consent, one join, saved entry,
  read-only retry, existing-record recovery, foreign results, close/late outcomes
  and caller cancellation. A real model→bridge→owner→storage/transport composition
  case covers uncertain accept, recovery, close and reopening with confirmed data.
- Full core **215/215 PASS**,14.981s:
  `/private/tmp/pinbook-ios-membership-screen-final-core.log`.
- Catalog **306 keys ×15 translated locales + English source** passes token and
  compiled Debug app/widget exact-parity checks. Both Chinese scripts and RTL
  languages are included. New translations are assistant drafts, not human review.
- Three UI cases are compiled for Chinese consent/confirmation, uncertain recovery
  without another join, and clearing on background. They are **not executed**.
- Initial Simulator compilation failed because this slice reused an existing asset
  file ID. Corrected only the new view's IDs; final build-for-testing **PASS**:
  `/private/tmp/pinbook-ios-membership-screen-fixed-test-build.log`.
- Unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-membership-screen-release.log`.

See VALIDATION.md for Release results and preserved intermittent localhost TLS
failure caveats. No new app-host/UI/physical/provider acceptance is claimed.

## Remaining integration

Invitation/account consent UI, root workspace lifecycle and reauthentication,
explicit original-invitation pending-acceptance retry, owner/invitation management,
real provider/origin configuration and final UX/security acceptance remain open.
`teams/acceptance` now has separately tested iOS transport, but is not exposed by
this screen or its current owner. A future null response must never clear
PENDING or trigger automatic replay; retain exact original identity/hash and require
fresh consent plus a durable generation for one same-identity retry.

All FINAL_UPDATE_CHECKLIST gates remain open. Existing financial data, archive
schema/keys, signing, source-push hold and TestFlight `0.1.0 (3)` are unchanged.
