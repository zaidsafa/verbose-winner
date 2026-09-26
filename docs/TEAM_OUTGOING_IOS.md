# Durable outgoing work

Updated September 27, 2026. `TeamOutgoingStore` is the protected SQLite owner for
editable drafts, immutable pending events, and exact encrypted retry bytes. The
default-off connected Team workspace now uses its new-note draft path. Correction
and review drafts remain local foundation only.

Drafts are scoped to the exact account, team, device and enrollment. Creation and
edits validate opaque IDs, nonnegative times, revision semantics and the existing
32 KiB exact UTF-8 text ceiling. Embedded NUL bytes are bound and read by explicit
byte length rather than C-string termination. Every edit and discard is a
compare-and-swap against the current draft version, so two editors cannot silently
overwrite one another.

Four event kinds are distinct: note submission, note correction, review approval
and review changes requested. A new submission has no base revision; corrections
and reviews require one. Submission and correction bodies must be nonblank.
Review comments may be empty because the explicit event kind carries the decision.
Reading or saving a draft never creates a review decision.

Only explicit `finalizeDraft` atomically inserts one immutable pending event and
removes its editable draft. A retry with the same event and draft identity is
idempotent after a committed but unobserved result. An event ID cannot alias a
different draft, and a finalized draft ID cannot be recreated while its pending
event exists. Stale finalization, queue capacity or storage failure leaves the
draft intact. Pending-event retirement requires an authenticated result bound to
the exact encrypted submission hash.

The dedicated `PinbookTeamOutbox/team-outbox.sqlite` is excluded from OS backup,
uses restricted permissions and iOS Complete file protection, plus rollback
journaling, `synchronous=EXTRA`, `fullfsync` and immediate transactions. It is not
SQLCipher or end-to-end encryption. It is capped at 100 drafts and 1,000 pending
events per exact sender enrollment. A replacement enrollment cannot submit or
adopt the old enrollment's queue automatically.

The connected composer restores one current new-note draft and exposes explicit
Save draft and Discard draft actions. Save does not require Terms acceptance and
does not finalize or upload. Send requires Terms, updates and finalizes that exact
draft identity, and then uses the existing canonical JWE retry path. Discard never
removes correction or review drafts.

Complete serial Swift validation is **422 tests in 39 suites PASS**. Localization
validation is **397 keys across English plus 15 translations**, and the ordinary
unsigned arm64+x86_64 Release Simulator build passes. Exact artifacts are in
`VALIDATION.md`.

The current encrypted payload still represents only a new text note. It does not
encode correction or review kind, base revision, server revision, attachments, or
off-device draft recovery. Those remain shared-contract and activation gates and
must not be inferred from the local event kinds.
