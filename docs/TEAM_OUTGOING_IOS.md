# Durable outgoing work — inactive iOS foundation

Updated September 5, 2026. `TeamOutgoingStore` is a local-only SQLite foundation
for editable drafts and immutable pending events. No production screen or network
route instantiates it.

Drafts are scoped to the exact account, team, device and enrollment. Creation and
edits validate opaque IDs, nonnegative times, revision semantics and the existing
32 KiB exact-UTF-8 text ceiling. Embedded NUL bytes are bound and read by explicit
byte length rather than C-string termination. Every edit and discard is a
compare-and-swap against the current draft version, so two editors cannot silently
overwrite one another.

Four event kinds are distinct: note submission, note correction, review approval
and review changes requested. A new submission has no base revision; corrections
and reviews require one. Submission/correction bodies must be nonblank. Review
comments may be empty because the explicit event kind carries the decision.
Reading or saving a draft never creates a review decision.

Only explicit `finalizeDraft` atomically inserts one immutable pending event and
removes its editable draft. A retry with the same event/draft identity is
idempotent after a committed-but-unobserved result; an event ID cannot alias a
different draft. Stale finalization, queue capacity or storage failure leaves the
draft intact. There is deliberately no pending-event deletion/retirement API yet:
future retirement requires an authenticated, exact server result.

The dedicated `PinbookTeamOutbox/team-outbox.sqlite` is excluded from OS backup,
uses restricted permissions and iOS Complete file protection, plus rollback
journaling, `synchronous=EXTRA`, `fullfsync` and immediate transactions. It is not
SQLCipher or end-to-end encryption. It is capped at 100 drafts and 1,000 pending
events per exact sender enrollment. A replacement enrollment cannot submit or
adopt the old enrollment's queue automatically.

Focused tests are **9/9 PASS**. Clean complete core is **318/318 PASS** after the
separate possession work, signed Simulator app-host is **346/346 PASS**, and the
same **346/346** app-host tests pass on the separate physical QA iPhone. The
ordinary unsigned Release build passes. Exact artifacts are in `VALIDATION.md`.

This does not define the encrypted wire event/envelope, assign a server revision,
submit or retry remotely, reconcile lost server replies, show user UI, recover
outgoing work off-device, or establish Android/iPhone sync. Those remain separate
shared-contract and activation gates.
