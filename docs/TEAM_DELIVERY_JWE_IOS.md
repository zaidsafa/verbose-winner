# Inactive iOS canonical team payload and multi-recipient JWE

Updated 2026-09-05 against frozen Android/server checkpoint
`b2a33120a1b96c117ebb6cac12a45e72db88c56f`.

## Plaintext payload

`TeamDeliveryPayloadCodec` accepts only this compact UTF-8 tuple:

```text
["pinbook-team-note-v1","<teamId>","<deliveryId>","<noteId>","<authorUserId>","<bodyBase64url>","<bodySha256>",0]
```

All IDs use the existing 1...128 ASCII identifier rule. The decoded UTF-8 body
must be nonblank and at most 32 KiB; its hash is exact lowercase SHA-256.
Attachments remain closed at zero. The full canonical payload is at most 45 KiB,
and decode must reproduce the exact input bytes. The caller supplies independently
authenticated expected team, delivery and author values. Only after those match
may authenticated server `acceptedAt` and fixed `expiresAt` form a recipient-local
envelope; server expiry never removes its durable local archive.

## Encryption envelope

`TeamDeliveryJWE` is canonical RFC 7516 General JSON with one A256GCM ciphertext,
one fresh 256-bit CEK and 96-bit IV, and 1...9 sorted recipient rows. Every row
uses a distinct fresh P-256 ephemeral key, ECDH-ES+A256KW, the existing RFC 7518
Concat KDF, and RFC 3394 wrapping. Each ephemeral key must be unique and distinct
from every recipient agreement key.

The exact protected header uses `crit:["pba","pbv"]`; `pba` is SHA-256 over the
canonical complete sorted recipient-thumbprint array. Decryption requires an
independently authenticated complete expected audience before retained agreement
custody is consulted. Unknown members, alternate order/serialization, noncanonical
base64url, invalid curves, duplicate/reordered/changed audiences, changed headers,
wrapped keys, ciphertext or tags all fail closed.

Caller plaintext and recipient public values are snapshotted before injectable
entropy/ephemeral callbacks. Mutable plaintext, CEK, IV, ECDH secret and derived
KEK copies are cleared on normal and throwing paths where Swift/CryptoKit exposes
their storage. Platform-provider internal key memory is not claimed zeroized.

## Authentication boundary and activation gate

JWE confidentiality/integrity is not sender authentication: anyone with the public
recipient keys can create another valid envelope. A future authenticated submit
transaction must bind the exact canonical-JWE SHA-256, stable delivery ID, sender
device, membership revision and frozen audience. Fetch must return that exact
stored identity and authenticated server metadata. The payload must be decoded,
compared and durably archived/verified before ACK.

This source is inactive. No normal UI, submit/fetch/ACK route, object provider,
background worker, server deployment, TestFlight upload or live synchronization
constructs it.

## Shared evidence

- `team-delivery-payload-v1.json` is byte-identical to the frozen shared fixture,
  SHA-256 `6b77c4c44048741fd4fd82ef0c8a244a6b949c3c00a82555c5f760d22bc353c7`.
- `team-delivery-jwe-v1.json` is byte-identical to the frozen shared fixture,
  SHA-256 `95d83009ccc53f6573edde6269d66ff6184fe3dbf518954edbcbcb0d5dc9e8a9`.
- Exact test/build/device artifacts are recorded in `VALIDATION.md`.
