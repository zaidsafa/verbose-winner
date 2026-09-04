# Device-authorized request wire for iOS — inactive

Updated September 5, 2026 from the corrected shared checkpoint
`dbeba7df0d64a637ea89fa2614cbe0b4fbeae97b`. This contains a bounded wire
primitive, public interoperability fixture, and two typed inactive client routes.
It adds no request signer, Secure Enclave transaction, generic callback, listener,
provider, delivery handler, stored request, or runtime activation.

## Exact local checks

`TeamDeviceRequestWire.message` accepts a strict challenge object, an app-owned
binding, the already-reviewed public enrollment key, the exact request body, and
current time. It returns canonical UTF-8 bytes only after checking:

- canonical HTTPS audience and every account/session/device/enrollment/key field;
- one closed operation value, team ID, stable request ID, and matching active-key
  RFC 7638 thumbprint;
- an exact 1...65,536-byte body and its lowercase SHA-256;
- strict challenge shape, canonical 32-byte challenge ID/nonce, safe integer time,
  access expiry, and a future deadline no more than 60 seconds away.

The message is the no-whitespace JSON array defined by the shared contract,
starting with `pinbook-device-request-v1`. The implementation does not accept
server-provided message bytes to sign. Its binding and diagnostics are redacted.

All four protocol operation names are reserved in the message grammar. The
corrected backend currently issues challenges only for `team-audience`; delivery
submit/fetch/ACK must remain inactive until each fixed coordinator exists.

Two typed HTTP methods use the existing authenticated onboarding client and its
shared unresolved-operation slot. Challenge sends exactly `enrollmentId` and the
nested `operation,teamId,requestId,bodySha256`. Execute sends exactly
`challengeId,signature,body`, where body is canonical unpadded base64url for
`{"membershipRevision":N}`. Before dispatch it revalidates the ticket, binding,
body, and deadline and verifies the signature against the exact prepared message
and reviewed enrollment public key.

The audience response accepts only the requested team/revision and at most nine
other-account targets. Account, device, and enrollment IDs must each be unique;
every exact public JWK must match its RFC7638 thumbprint. Recipient discovery is
not completed note delivery or authorization to ACK anything.

## Evidence and next boundary

The copied fixture is byte-for-byte identical to
`shared/team-device-request-v1.json`. Swift rebuilds the exact message/body digest,
matches the declared message digest, verifies the raw 64-byte P-256 signature in
CryptoKit, rejects a changed message, and rejects every binding/body/public-key
substitution. It also tests body, shape, access, and one-minute deadline bounds.
Exact local and physical-iPhone counts are in `VALIDATION.md`.

The next narrow layer is a one-flight audience owner that composes current account
generation, exact REGISTERED device generation, server enrollment and membership
revision around these routes. Signing must use that exact retained device and
recheck the pinned account session before and after the device transaction. There
is still no generic transaction callback or raw PostgreSQL client. Submit/fetch,
encrypted delivery and archive-before-ACK remain separate gates.
