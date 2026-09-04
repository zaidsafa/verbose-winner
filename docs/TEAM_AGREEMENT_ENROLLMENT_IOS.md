# iOS agreement-key enrollment — inactive

Updated September 5, 2026 against corrected Android/server contract
`0011c1d4f9719ab0137632ecd3485676c6a54cad`.

`TeamAgreementEnrollment` is a foreground, one-flight composition of one exact
reviewed account generation, registered signing-device generation, current team
membership, and separate enrollment-scoped P-256 agreement identity. It is not
reachable from normal app navigation.

Each explicit operation:

- reloads and pins the exact local registered device and confirms the same active
  enrollment/signing thumbprint remotely;
- obtains a fresh current membership revision for the exact team;
- prepares or reopens the separate non-exportable agreement identity and rejects
  reuse of the local signing credential;
- creates a random 256-bit request ID and canonical ASCII body containing exactly
  `agreementKey` (`crv,kty,x,y`) and `membershipRevision`;
- obtains the closed `device-agreements/challenge`, rebuilds the exact
  `pinbook-device-request-v1` message locally, and signs it with the registered
  signing key while current account authority is checked inside custody;
- executes once and accepts only the exact team, revision, enrollment, agreement
  JWK and RFC 7638 thumbprint that were signed.

Account generation, device generation, agreement identity, wall/monotonic time,
access expiry and proof expiry are rechecked around every await. There is no
retry, replacement, polling or background work. Cancellation keeps the one-flight
slot busy until a noncooperative dependency actually settles.

The audience response now requires both signing and agreement JWK/thumbprint for
every recipient. Missing or malformed agreement credentials reject the whole
snapshot; the client never silently removes a recipient. Agreement/signing reuse
is rejected locally, while the corrected server contract rejects collision with
any retained signing credential.

Clean focused owner/HTTP/audience/custody tests are **43/43 PASS** and complete
core is **307/307 PASS**. Unsigned generic-iOS app/test compilation and ordinary
unsigned Release pass. Exact artifacts are in `VALIDATION.md`.

This checkpoint is source-only: no phone run, live endpoint, provider login,
listener, deployment, production data, encrypted note, submit/fetch/ACK or
TestFlight update. Signing authorization proves the registered device approved
the agreement public key, but it does not cryptographically prove a hostile
client owns the corresponding agreement private key. Native custody does own it;
an explicit ECDH key-confirmation design is still required before staging.
