# iOS membership screen — inactive integration surface

Updated 2026-09-05. This adds a native, localized membership confirmation and
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
5. An explicit original-link retry entry now displays **Check previous join**.
   It can reconcile an already-completed join without another accept, or show
   previous-attempt guidance and NEW unchecked consent before **Retry join**.
   Errors cannot automatically resend. See TEAM_MEMBERSHIP_RETRY_IOS.md for the
   real owner/bridge composition and token lifecycle; no code enters UI state.

The screen explains that joining does not share existing private notes and that
shared-note delivery is not enabled. Native glass buttons, semantic text colors,
theme surfaces, a scrollable 560-point maximum content width, wrapping text and
Reduce Motion-aware transitions reuse the app's design. No cropped screenshot or
compiled source is evidence of live accessibility/contrast acceptance.

## Test-only host and evidence

DEBUG presentation requires BOTH an ephemeral `-PinbookFixture` and explicit
`-PinbookTeamMembership`. Whitelisted `-PinbookMembershipScenario` values are
`success`, `uncertain`, `recovery`, `retry-pending`, `retry-joined`. These actors use public synthetic values only,
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
- Three UI cases now **PASS on the separately installed physical Pinbook QA app**:
  Chinese consent/confirmation, uncertain recovery without another join, and
  clearing on background. See DEVICE_QA_IOS.md for exact results. The original
  compiled-only checkpoint below is historical. Visual review found bright-accent
  button text needing correction; a shared native prominent style now fixes this.
  All10 skin/appearance screenshots and the final Chinese confirmation were
  visually inspected after correction, in addition to passing behavior tests.
- Initial Simulator compilation failed because this slice reused an existing asset
  file ID. Corrected only the new view's IDs; final build-for-testing **PASS**:
  `/private/tmp/pinbook-ios-membership-screen-fixed-test-build.log`.
- Unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-membership-screen-release.log`.

See VALIDATION.md for Release results and preserved intermittent localhost TLS
failure caveats. Physical QA results do not imply real provider or team activation.

## Remaining integration

Invitation/account consent UI, root workspace lifecycle and reauthentication,
parent routing into original-invitation retry, owner/invitation management,
real provider/origin configuration and final UX/security acceptance remain open.
`teams/acceptance` now composes through the retry screen's retained bridge and real
owner. A successful null response only prepares fresh consent; it never clears
PENDING or triggers automatic replay. Exact original identity/hash and a durable
generation remain required for one explicit same-identity retry.

All FINAL_UPDATE_CHECKLIST gates remain open. Existing financial data, archive
schema/keys, production signing, source-push hold and TestFlight `0.1.0 (3)` are
unchanged. Only the separate owner-approved development QA identity is installed.
