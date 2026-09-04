# Inactive iOS delivery submit intent

Updated 2026-09-05 against frozen Android/server checkpoint
`a158bf8f1c83bb2813009d835d0b079999d25187`.

`TeamDeliverySubmitIntentCodec` freezes metadata for a future authenticated
device request. Its exact compact printable-ASCII JSON member order is:

```text
audienceDigest, deliveryId, jweBytes, jweSha256, membershipRevision, type
```

The audience digest is the canonical 32-byte JWE `pba`; delivery ID follows the
existing protocol-ID rules; JWE length is 1...100000 bytes and its SHA-256 is
lowercase hexadecimal; membership revision is 0...9007199254740991; and type is
exactly `pinbook-delivery-submit-v1`. The complete intent is at most 512 bytes.
Decode compares caller-supplied expected delivery ID, membership revision and
audience digest, then re-encodes and compares exact input bytes.

`fromCanonicalJWE` snapshots and hashes exact printable-ASCII JWE bytes.
`verifyCanonicalJWE` rechecks length and digest. These operations intentionally
do not assert that the JWE is structurally valid or authorized; payload/JWE
validation, current account/device/enrollment, sender proof, fresh membership,
object-provider state and server acceptance remain separate mandatory gates.

The later server-only schema checkpoint
`5d6bbf3b6cfb1178e0e6dd96e4ad560e1b44e568` records the same comparison fields
plus sender device/enrollment, accepted time and fixed expiry. No iOS schema port
was requested at this checkpoint. Future composition must preserve those fields,
make only `ACCEPTED` rows fetch-visible, and maintain durable archive/verification
before ACK.

This source performs no network request, upload, provider access, database write,
acceptance, retention countdown, ACK, UI action, TestFlight upload or live sync.

The copied shared fixture is byte-identical, SHA-256
`02c4cdcbcea9e50e0e9066c5618245f321e6ec06a8854129858c44459a136b17`.
Exact validation evidence is in `VALIDATION.md`.
