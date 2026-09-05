# Pinbook iOS encrypted delivery receive boundary

Status: implemented and tested locally; runtime and ACK transport remain disabled.

## Completed boundary

`TeamDeliveryReceiveCoordinator` accepts only a result already returned by the
authenticated device fetch flow. Before plaintext persistence it rebinds the
delivery, team, account, device and enrollment to the signed fetch binding;
rechecks immutable lifetime, serialized-byte count and SHA-256; requires exact
UTF-8 JWE bytes; validates the independently authenticated full recipient set;
decrypts through retained agreement-key custody; and strictly decodes the
canonical team-note payload with the expected author.

The decrypted note is then passed to `TeamInboxStore.receive`, whose single
SQLite transaction writes the immutable local archive, a delivery-to-ciphertext
SHA-256 binding, and the exact pending receipt. Successful return requires that
exact ciphertext-bound receipt to be readable. An exact redelivery is idempotent;
changed content or ciphertext hash remains an immutable conflict.

Schema v2 replaces the unsafe v1 receipt field, which held a plaintext digest.
Migration preserves every archived note, deletes only those unsendable receipts,
and requires a fresh authenticated fetch before establishing a new ciphertext
binding. The frozen local ACK body is exactly
`{"deliveryId":"D","jweSha256":"<64 lowercase hex>","type":"pinbook-delivery-ack-v1"}`.
It is not connected to HTTP yet. Receipt retirement requires an explicit
authenticated result class: `ACKED`, `CANCELLED`, `EXPIRED` or `PURGED`.

Plaintext working bytes are cleared after decoding. The archive database remains
file-protected, backup-excluded and separate from personal backup data.

## Fail-closed rule

There is no authenticated ACK HTTP route in server commit `33410b6c` or the
shared frozen contract. This code never sends or claims an ACK. A validation,
decryption, archive, capacity or receipt-write failure produces no ACK-capable
result. Pending receipts remain durable and unsent until Android/server publishes
an exact authenticated ACK route, body, response and idempotency contract.

## Evidence

- Focused Swift Testing: `TeamDeliveryJWETests` 6/6 pass.
- Focused v1-to-v2 migration: 1/1 pass.
- Complete Swift package regression: 382/382 pass.
- Unsigned Release iOS Simulator build against SDK 26.5: pass.
- Production identity remains `com.zaidsafa.pinbook.ios`; no version/build,
  provider, phone, server, archive, TestFlight or production action occurred.
