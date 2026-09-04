# Agreement private-key confirmation proposal — superseded

Status: historical design only. Superseded September 5, 2026 by the reviewed
Android/server contract `TEAM_AGREEMENT_POSSESSION_V1.md` at
`fdfa0a883af409d0fd02a47aaeeaed15b66e1400` and the byte-identical public vector
`team-agreement-possession-v1.json`. Do not implement the proposed bytes below.

The accepted contract uses `agreementServerPublicKey` plus
`agreementServerKeyThumbprint`, PartyU=`challengeId`,
PartyV=`agreementKeyThumbprint`, and HMAC purpose
`pinbook-agreement-possession-v1`. iOS parity and evidence are documented in
`TEAM_AGREEMENT_ENROLLMENT_IOS.md` and `VALIDATION.md`.

## Threat and goal

The registered signing device currently authorizes an agreement public key, but a
modified client could submit a valid public key whose private half it does not
hold. Before staging, the server must verify possession of the exact agreement
private key while retaining the existing registered-device signature,
membership-revision binding and immutable enrollment record.

This proof does not attest genuine app code, hardware class or user identity. It
only confirms possession of the private key corresponding to the authorized
agreement JWK during this one enrollment attempt.

## Proposed flow

Keep the existing canonical agreement body unchanged. Extend only the closed
agreement routes:

1. `device-agreements/challenge` receives the existing enrollment and binding,
   including the canonical body SHA-256.
2. After all current session/device checks, the server creates a fresh ephemeral
   P-256 agreement key for this pending challenge. The reply contains the existing
   device-request challenge fields plus exact `confirmationKeyId` and
   `confirmationPublicKey` (`crv,kty,x,y`). The server retains the ephemeral
   private key only inside the bounded, expiring pending challenge.
3. The client validates the server P-256 point, derives ECDH using the exact
   enrollment-scoped agreement private key, derives a 256-bit confirmation key,
   and computes a 32-byte HMAC tag over the canonical context below.
4. The registered signing key still signs the existing
   `pinbook-device-request-v1` message, which already binds body digest, request
   challenge, enrollment, team, request ID and deadlines.
5. `device-agreements/execute` adds one exact `confirmationTag` field. The server
   consumes the pending challenge before any await, independently verifies the
   device signature and agreement HMAC, reruns all current authority/membership/
   collision checks, then performs the same immutable insert/exact idempotence.

No static server ECDH private key is proposed. Fresh ephemeral keys avoid a new
long-lived Infrastructure secret and make each confirmation challenge one-use.

## Proposed exact bytes

After shared review, derive:

```text
K = ConcatKDF-SHA256(
  Z = P-256-ECDH(agreementPrivate, serverEphemeralPublic),
  AlgorithmID = "pinbook-agreement-confirm-v1",
  PartyUInfo = UTF8(agreementKeyThumbprint),
  PartyVInfo = UTF8(confirmationKeyId),
  keydatalen = 256
)
```

The HMAC input would be compact JSON with no whitespace/newline:

```text
JSON.stringify([
  "pinbook-agreement-confirm-v1", audience, authorityEpoch, accountId,
  sessionId, deviceId, enrollmentId, teamId, requestId, bodySha256,
  challengeId, nonce, expiresAt, agreementKeyThumbprint, confirmationKeyId
])
```

`confirmationTag = HMAC-SHA256(K, message)`, encoded as canonical unpadded
base64url32. The client and server clear `Z`, `K`, tag working copies and the
server ephemeral private key when the pending record settles or expires.

The exact field ordering, KDF parameters and message above are a proposal, not a
contract. A public Android/JCA, iOS/CryptoKit and Node vector must be generated
from independently created ephemeral keys and checked in all three runtimes before
any route changes.

## Required failure behavior

- Unknown, expired, replayed or restarted challenges fail; no automatic retry.
- Wrong server point/key ID, agreement key, body digest, membership revision,
  session/device/enrollment binding, deadline, device signature or HMAC fails the
  entire transaction.
- Confirmation cannot authorize replacement. Exact idempotence remains limited to
  the already-retained same enrollment/epoch/key.
- Agreement keys colliding with any retained signing credential remain forbidden.
- Missing confirmation never falls back to signing-only enrollment.
- A lost execute response is uncertain; reconciliation must read the exact
  immutable agreement registration before a newly authorized attempt.

## Evidence required before staging

- Independent public vectors: ECDH secret, Concat KDF input/output, canonical
  confirmation message and tag, with private fixtures excluded from release data.
- Malformed-point, changed-field, changed-body, wrong-key, replay, expiry, restart,
  collision, concurrent exact-idempotence and zero-row rollback tests.
- Real Android Keystore API35+ and iPhone Secure Enclave derivation against the
  same server-generated public fixture.
- Bounded pending-key memory, constant-time tag comparison and no secret logging,
  persistence, crash dump copy or response echo.
- Infrastructure review of process restart semantics and abuse/resource limits.

Only after this gate may the multi-recipient envelope itself be frozen.
