# Final Pinbook iOS update gate

Owner instruction September 4, 2026: build 0.1.0 (3) is good; no incremental
TestFlight uploads. Next update must cover the complete agreed scope and final
regression. This checklist distinguishes shipped capabilities from unfinished
ones; neither compiled source nor a placeholder counts as a completed feature.

## Preserve and revalidate in the final candidate

- [ ] Native Liquid Glass navigation, elegant motion, Reduce Motion and Dynamic Type.
- [ ] Fresh first-run experience without deleting existing users' records; simple,
      skippable introduction with clear language selection.
- [ ] All 16 language catalogs, including both Chinese scripts; live switching,
      RTL, translated errors and onboarding; no missing format arguments.
- [ ] Five themes: readable text/controls in light and dark appearance, clear
      names, descriptions and symbols at selection.
- [ ] Currency catalog with localized names, symbols and unambiguous ISO codes;
      search, favorites, selection and correct localized amount precision.
- [ ] Bright app icon in the installed app, widget gallery and App Store Connect.
- [ ] Expenses, settlements, balances, notes, templates, receipts, reminders,
      statements, personal backup-v8 preview/merge/recovery without data loss.
- [ ] Both iPhone widgets: clear privacy behavior and verified installation/deep links.
      Current Balance Overview is an entry point, not live shared-container data.
      Live balances require explicit App Group/capability and privacy integration.

These items exist in the published baseline to varying documented extents; final
checkboxes deliberately remain open until checked against the exact next candidate.

## Unfinished functionality: not allowed to disappear from scope

- [ ] Personal cloud integration: distinguish manual Files destinations (implemented)
      from automatic Drive/iCloud sync (not implemented). Final provider behavior,
      OAuth/capabilities, consent, conflicts, failures and recovery must be agreed
      and verified; do not advertise simultaneous providers without a safe design.
- [ ] Invite-only team sign-in, account/session admission, enrollment, roles,
      revocation and account lifecycle. Provider preference is coordinated by
      the Android task; do not send duplicate owner prompts.
- [ ] Reviewed group-encryption library/provider, crash-safe crypto state, bounded
      untrusted input, key rotation, offline catch-up and authorized rejoin.
- [ ] Durable outgoing notes/drafts, revisions and reviews as distinct events;
      no implicit approval just because a delivery was read or saved.
- [ ] Team inbox and authenticated retries/ACKs, account/team/enrollment isolation,
      expiry/missing-item explanations and preservation of local archives.
- [ ] Supported media with complete verification before ACK; explicit caps and
      interrupted-download/upload recovery. Current local foundation is text only.
- [ ] Recovery-key custody/consent, secure Files export/import and cleanup, preview,
      lost-key/backup-health explanations, sender/revision/media coverage, and
      Android -> iOS -> Android full recovery without restoring remote authority.
- [ ] Isolated Infrastructure admission/staging, privacy metadata and accurate
      retention/deletion wording, provider purge/restore tests. No direct shared
      infrastructure access or deployment outside its owning task.

## Current local implementation checkpoint

- Received-text local store and restricted encrypted portable archive implemented;
  public cross-platform fixture round trip passed. No production entry point.
- Bounded file reader and immutable authenticated restore candidate implemented.
  Preview is read-only; confirmation revalidates conflicts atomically.
- Bounded local inbox paging and device-only recovery-key custody implemented
  behind inactive APIs. No normal app screen opens the team store or creates keys.
- See `VALIDATION.md` for exact tested checkpoints. This is not a complete user
  recovery flow or a physical-device acceptance claim.
- Crypto audit/version/fix assessment: `OPENMLS_AUDIT_ADOPTION_20260904.md`.

## Final publication gates

- [ ] Resolve scope/provider/access decisions without silently dropping features.
- [ ] Complete implementation and integration, not disabled foundations.
- [ ] Full automated app/UI suites, localization and accessibility checks.
- [ ] Synthetic cross-platform full-workflow and staging failure/recovery acceptance.
- [ ] Resolve physical-only acceptance separately; owner may keep phone disconnected
      during development. Simulator passes do not close hardware gates.
- [ ] Review privacy/review notes, version/build, archive signature and upload artifact.
- [ ] Only then publish one final candidate to all existing TestFlight groups and
      verify processing, group availability and any required external review.

No new upload, version increment, release archive or signing mutation is authorized
merely by completing one checkbox. Never label this whole checklist complete based
on the owner's positive feedback about build 3.
