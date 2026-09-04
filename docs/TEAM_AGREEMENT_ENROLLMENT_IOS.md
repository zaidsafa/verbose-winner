# iOS agreement-key enrollment — inactive

Updated September 5, 2026 against corrected enrollment contract
`0011c1d4f9719ab0137632ecd3485676c6a54cad` and frozen Android/server possession
contract `fdfa0a883af409d0fd02a47aaeeaed15b66e1400`.

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
- sends the proposed public-only agreement JWK to the closed
  `device-agreements/challenge`, requires a fresh server P-256 public JWK with its
  matching RFC 7638 thumbprint, and rejects private, malformed, mismatched or
  reflected server keys;
- rebuilds the exact
  `pinbook-device-request-v1` message locally, and signs it with the registered
  signing key while current account authority is checked inside custody;
- proves possession of the separate agreement private key through P-256 ECDH,
  frozen RFC 7518 Concat KDF parameters and the exact
  `pinbook-agreement-possession-v1` HMAC context, then sends the canonical 32-byte
  confirmation alongside the existing signature and body;
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

The public vector is byte-identical to Android/server (SHA-256
`946a6bfda62b193c23a38a53e6a3f4293fdc725545e3deefd99c567c63c763c2`).
Focused agreement tests are **13/13 PASS** plus the exact HTTP route test. Clean
complete core is **318/318 PASS**; signed Simulator and separate physical-QA
iPhone app-host suites are each **346/346 PASS**. The physical run includes the
named Secure Enclave possession confirmation against an independent software
peer. Ordinary unsigned Release passes. Exact artifacts are in `VALIDATION.md`.

This remains inactive: no live endpoint, provider login, listener, deployment,
production data, encrypted note, submit/fetch/ACK or TestFlight update. The former
private-key-possession gap is closed at source/vector/physical-iPhone level, but
server staging, restart/expiry behavior and the multi-recipient encrypted envelope
remain required before live delivery.
