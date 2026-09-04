# Retained invitation workflow UI

Updated September 5, 2026. Pinbook now has a native retained parent presentation
for invitation account access -> device registration -> membership review. The
ordinary app does not route to it yet; the DEBUG QA host uses public synthetic
fixtures and never opens Keychain, provider login, network, or stored records.

## Three separate decisions

1. Account: review the team and role, then explicitly continue with the exact
   shown account or enable a new-account sign-in consent. The account receipt is
   display context, not device or membership authority.
2. Device: review the exact account/team, enable a newly unchecked registration
   consent, then register. Registration does not join the team or share private
   notes. Waiting, retry-ready, and uncertain results cannot advance. Every
   explicit continuation or retry requires fresh consent; no request is replayed
   automatically.
3. Membership: review the team and role again, enable a separate newly unchecked
   membership consent, then join. Device registration never implies this consent.

The parent retains every transition task and validates account, team, and role
before mounting the returned child. It closes and drains the outgoing screen
before publication. A cleanup uncertainty fails closed instead of advancing.
Late, cancelled, or mismatched child products are closed and never displayed.

## Lifecycle and presentation

Backgrounding or closing invalidates the entire workflow and drains account,
device, membership, and transition work. The real host must also recreate it for
an external account/session-generation replacement. Merely arriving on a screen
does not start provider, device, or membership I/O.

`TeamDeviceRegistrationView` uses localized status, privacy copy, account/team
context, one fresh consent toggle, explicit action, wait guidance, and a distinct
Continue action only after confirmed registration. It follows the current skin,
Dynamic Type, RTL, Reduce Motion, and system semantic foreground colors.

## Evidence boundary

Core model tests cover separate decisions, retry consent, malformed waits,
uncertainty, cancellation, mismatched context, cleanup failure, and lifecycle
invalidation. Physical-iPhone UI tests cover Chinese and Arabic presentations,
all three decisions, retry consent, uncertain no-replay behavior, and background
closure. Exact counts and artifacts are recorded in `VALIDATION.md` and
`DEVICE_QA_IOS.md`.

This checkpoint does not establish live Apple/Google issuance, real device
enrollment, team-note delivery, Android/iPhone synchronization, normal-navigation
activation, or final TestFlight readiness. It changes no production bundle ID,
capability, version, archive, or TestFlight build.
