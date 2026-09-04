# Device-authorized request wire for iOS — inactive

Updated September 5, 2026 from the corrected shared checkpoint
`dbeba7df0d64a637ea89fa2614cbe0b4fbeae97b`. This is a bounded wire primitive
and public interoperability fixture only. It adds no HTTP route, request signer,
Secure Enclave transaction, generic callback, listener, provider, delivery
handler, stored request, or runtime activation.

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

## Evidence and next boundary

The copied fixture is byte-for-byte identical to
`shared/team-device-request-v1.json`. Swift rebuilds the exact message/body digest,
matches the declared message digest, verifies the raw 64-byte P-256 signature in
CryptoKit, rejects a changed message, and rejects every binding/body/public-key
substitution. It also tests body, shape, access, and one-minute deadline bounds.
Exact local and physical-iPhone counts are in `VALIDATION.md`.

The next narrow layer may add the two typed inactive HTTP routes from the corrected
contract: challenge and execute. Execute body decoding is a separate strict schema;
there must be no generic transaction callback or raw PostgreSQL client. Signing
must later use the exact REGISTERED device generation, with pinned account session
checks before and after the device transaction. Those integrations are not part of
this checkpoint and cannot be inferred from successful public-vector verification.
