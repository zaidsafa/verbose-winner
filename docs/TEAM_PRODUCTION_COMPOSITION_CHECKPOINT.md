# Team production composition checkpoint

Status: source-complete bounded slice; production remains default-off.

Implemented:

- all-or-empty public build configuration for the HTTPS service origin, Apple
  client ID, Google native/server client IDs, authority epoch, Terms and Privacy
  URLs, and invitation host;
- one inert strict HTTP foundation for auth, onboarding, device registration,
  membership/invitations, delivery and migration-027 compliance routes;
- exact migration-027 Terms, report, block/unblock, deletion request and
  credential-bound deletion-status wire validation;
- connected-account actions for Terms acceptance, encrypted note send, foreground
  receive/archive-before-ACK, member invitation, report/block/unblock and deletion;
- account-global SQLite erasure, device/join metadata erasure, agreement-key
  erasure, all-team Terms erasure and exact account-session erasure;
- real archived-note/member presentation, fixed report reasons, pending/error UI,
  ShareLink and local QR output; no manual safety identifiers;
- opt-in Associated Domains entitlement plus deterministic AASA generation.

No live origin, provider credential, secret or fallback domain is committed.
Normal Debug/Release values are empty and the runtime remains disabled. A release
owner must still supply the complete ignored build configuration, connect the
pre-connection Apple/Google create/join onboarding owner to the runtime injection
seam, deploy migration 028 workers, publish and validate AASA, enable the App ID
capability/provisioning profile, and pass physical iOS/Android staging acceptance.

This checkpoint is not TestFlight or production approval. No signing identity,
version/build number, provider console, server, device or store state is changed.

Validation at this checkpoint:

- complete Swift package: 414 tests in 39 suites pass;
- 371 localization keys are complete across English plus 15 translations, with
  compiled app/widget localization plists valid;
- plist/project/entitlement lint and `git diff --check` pass;
- unsigned Release Simulator build passes for arm64 and x86_64 at
  `/private/tmp/pinbook-composition-derived`, retaining bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`;
- all eight Team production settings remain empty in the produced app;
- generated AASA JSON validates with app ID
  `F98S3VN5NL.com.zaidsafa.pinbook.ios`.
