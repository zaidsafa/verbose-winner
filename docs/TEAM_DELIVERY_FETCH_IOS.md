# Inactive authenticated delivery relay checkpoint

Updated: 2026-09-05 (Asia/Shanghai)

## Frozen source contract

This checkpoint matches Android/server commit
`b88454bc37f7b30d2fb0df161e268fd6a901f8e6`. It is deliberately default-off and
adds no production origin, provider, background task, retry loop, navigation or
TestFlight behavior.

- Pending-list, ciphertext-fetch, receipt-ACK and submission-status operations
  all obtain an operation-bound challenge from
  `POST /api/v1/deliveries/challenge`.
- Their authenticated execution routes are exactly
  `POST /api/v1/deliveries/pending`, `POST /api/v1/deliveries/fetch`,
  `POST /api/v1/deliveries/ack` and
  `POST /api/v1/deliveries/submit/status`.
- Pending-list requests use a strict limit of 1...50 and optional
  `(acceptedAt, deliveryId)` keyset cursor. Results must be strictly ordered,
  unique, newer than the supplied cursor and internally consistent with
  `hasMore` and `nextCursor`.
- Every pending descriptor freezes the sender, accepted/expiry timestamps,
  encrypted byte count and SHA-256, audience digest and agreement-key
  thumbprint. The fetch response must repeat and exactly match the immutable
  delivery, time, size, hash, audience and local agreement-key bindings before
  any decryption or archive mutation.
- ACK accepts only the exact delivery/JWE hash pair already stored in the
  durable receipt. An authenticated `ACKED` response retires only that receipt
  and preserves the protected archive. Other transport/server errors preserve
  the receipt for a later foreground retry; an authenticated terminal HTTP 410
  retires it as cancelled while preserving the archive.
- Submission status is signed and accepts only an exact known delivery/JWE hash.
  Its state, reservation lifetime, acceptance/expiry pair and immutable hash are
  parsed fail-closed with no automatic retry.
- The existing device-request message binds the current account session, device,
  enrollment, authority epoch, team, operation, body hash and access expiry.
- The client revalidates the signature before dispatch and rechecks the access
  ticket after the response. There is no automatic retry.
- Fetch requires canonical base64url; decoded encrypted bytes, declared size and
  lowercase SHA-256 must match both the list descriptor and the response.
- Decoded JWE bytes are limited to 1...100,000 bytes. The complete HTTP response
  is independently capped at 140,000 bytes, allowing the canonical base64url
  envelope while rejecting larger responses before parsing.

## Evidence

- Focused relay transport/receive coverage passed **4/4**, including exact routes,
  operation bindings, cursor/metadata rejection, ACK retirement, terminal 410
  handling and preservation on retryable failure.
- Complete isolated Swift validation passed **386 tests in 37 suites**, zero
  failures, using `/private/tmp/pinbook-relay-spm`.
- `git diff --check` passed.
- The unsigned production Release iOS Simulator build passed for arm64 and
  x86_64 using `/private/tmp/pinbook-relay-derived`; bundle identity remained
  `com.zaidsafa.pinbook.ios`.

## Explicit non-claims

This is an authenticated transport and local archive/receipt lifecycle boundary,
not a completed team-sync feature. It does not schedule foreground refresh,
retry a durable outbox, enable push, provide production UI, deploy the server or
prove Android-to-iOS delivery under real infrastructure. Server activation still
depends on journal-v2. Sign in with Apple equivalence, in-app account deletion,
Terms, user reporting/blocking and complete privacy-manifest declarations also
remain App Store readiness gates. No phone, provider, server, TestFlight or
production action occurred.
