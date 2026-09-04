# Pinbook iOS delivery journal event v1 — inactive parity

Updated 2026-09-05. This is a local model and canonical-vector checkpoint only.
It does not create a submit endpoint, object provider, journal writer, fetch, ACK,
database projection, account authority or live sync route.

## Frozen contract

The iOS ACCEPT model mirrors committed Android/server checkpoint `2725a49`:

- deterministic `eventId = accept-<jweSha256>` and `objectId = jweSha256`;
- exact delivery, team, sender user/device/enrollment and authority epoch;
- membership revision, audience digest, canonical submit-intent SHA-256, JWE byte
  count and SHA-256;
- created, reservation-expiry, write-started, object-verified, accepted and fixed
  30-day expiry timestamps;
- 1...9 targets in strictly increasing agreement-key-thumbprint order, with exact
  user/device/enrollment/agreement-key-thumbprint identity.

Validation rejects unsafe IDs, noncanonical digests, duplicate users/devices/
enrollments, the sender in the audience, changed ordering or audience digest,
deadline inversions, reservations over 15 minutes and unsafe integer times. The
canonical constructor requires the exact re-encoded submit-intent bytes and derives
their SHA-256; callers cannot supply the deterministic event/object IDs or expiry.

ACK and CANCEL models freeze the same four-field target, including
`agreementKeyThumbprint`. CANCEL permits only `MEMBERSHIP_REMOVED`. All event and
target diagnostic descriptions/reflection are redacted.

## Canonical vector and evidence

The accepted-event serialization uses the server's recursively sorted JSON member
order. Independent Node construction from the shared JWE and submit-intent fixtures
produces exactly 1,079 bytes and SHA-256
`253037999a2c6122c96de38e1123f7b3923202670e98c418575d34f9f23a4a7f`.
The canonical submit-intent digest inside that event is
`b39a539699af95520162e09fe08ee4044e66bf80de3968ee24f356e043561ddf`.

- Focused journal-event Swift tests: **4/4 PASS**.
- Complete Swift core: **332/332 PASS**, 29 suites.
- Signed iOS 26.5 Simulator app-host: **357 PASS + 4 expected physical-only
  SKIPS**, 361 total, 0 failures.
- Ordinary unsigned production Release: **BUILD SUCCEEDED** with unchanged bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`.

Exact logs/results are recorded in `VALIDATION.md`. Server checkpoint `12137d2`
later tightened inactive lease/recovery behavior without changing this accepted-
delivery event contract. Provider writes, journal commit authority, recovery,
archive-before-ACK, two-device sync and staging acceptance remain outside this
iOS checkpoint.
