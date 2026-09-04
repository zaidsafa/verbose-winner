# Portable team archive v1

Status: disabled local foundation; no user export/import UI, cloud integration, media, or group
encryption. Implemented jointly with Pinbook iOS. Never transfer the native Room/SQLite DB.

## Encryption profile

Restricted JWE Compact Serialization per [RFC 7516](https://www.rfc-editor.org/rfc/rfc7516)
and AES-GCM per [RFC 7518](https://www.rfc-editor.org/rfc/rfc7518). This is a narrow profile,
not a general JOSE implementation or a claim of cryptographic audit.

- Exact protected header UTF-8 bytes (including this key order, no whitespace):
  `{"alg":"dir","enc":"A256GCM","typ":"pinbook-team-archive-v1"}`.
- Random 32-byte user-held recovery key, NOT a password, login token or server-held key.
  No production key is checked into source or emitted in diagnostics. Key custody/export UI
  remains a launch gate. Losing both device/key can make a backup unrecoverable.
- Fresh provider-generated 12-byte nonce per encryption; 16-byte authentication tag.
  Public production API never accepts a caller-supplied nonce.
- Five compact segments: protected header, empty encrypted-key segment, nonce, ciphertext, tag.
  AAD is ASCII of the unpadded base64url protected-header segment.
- Strict canonical unpadded base64url; reject whitespace, padding, nonzero unused pad bits,
  extra segments, alternate headers/algorithms, compression, external key references.
- Authenticate before parsing or returning plaintext. Android uses JCA AES/GCM/NoPadding;
  iOS uses CryptoKit AES.GCM. Temporary plaintext byte buffers are cleared where possible;
  managed-runtime Strings/copies cannot be promised to be zeroized.
- Ciphertext at most 16 MiB; plaintext at most 16 MiB; compact input at most 22,370,000 ASCII
  characters. Future file pickers must enforce bounded streaming reads before loading input.

## Plaintext profile

Strict UTF-8 JSON, no BOM, malformed bytes or unpaired surrogates. No Unicode normalization.
Root is exactly this four-element array; every scalar is a string:

```json
["pinbook-team-archive-v1", "accountId", "exportedAt", [
  ["teamId", "deliveryId", "noteId", "authorUserId", "recipientDeviceId",
   "recipientEnrollmentId", "body", "bodySha256", "acceptedAt", "expiresAt", "savedAt"]
]]
```

Each record has exactly eleven string fields. No objects, extra fields, numeric tokens, nulls,
comments, trailing input, or coercion. Valid JSON whitespace/escaping is accepted. Timestamps
are canonical nonnegative decimal Int64 strings: `0` or `[1-9][0-9]*`, no leading zero, plus,
fraction, exponent or overflow. Server wire timestamps will use the safe-integer subset, not
arbitrary JavaScript floating-point conversions.

Maximum 10,000 records per file and 16 MiB of serialized UTF-8, both enforced independently.
Empty exports are valid. Oversized exports fail, never truncate silently; multi-file partitioning
and large-archive UX remain future work. IDs, body limit (32 KiB), lowercase unnormalized UTF-8
SHA-256, immutable thirty-day expiry and sender/recipient rules match the local delivery contract.
Account is bound to an explicitly supplied expected account, with no silent remapping.
Duplicate `(teamId, deliveryId)` records reject the entire file even when identical.

## Restore safety

Validate/decrypt all input before import. Import within a single database transaction, reject
immutable conflicts, retain existing savedAt for identical deliveries. Any storage or validation
failure leaves no partial import. Restored device/enrollment IDs are historical, not credentials.
Import never creates/deletes delivery receipts, changes membership, resets expiry, contacts the
server or restores revoked access. Existing receipts are preserved unchanged. Relay cleanup
never removes the imported local archive.

This initial archive schema represents received text deliveries only. Sender-owned drafts/events,
review revisions, attachments and explicit multi-file archives require subsequent model work;
do not enable a real pilot claiming complete recovery until those are covered and tested.

## Shared test vector

`shared/team-archive-v1-vector.json` SHA-256:
`4a92f6b9f1f940daf73f8ed3774354ed3ef883ab0c397319da03f15da397d504`.
Generated with Node.js AES-256-GCM and checked by Android JCA/iOS CryptoKit. It intentionally
contains a PUBLIC TEST key (`00..1f`) and nonce (`00..0b`), not credentials. Never use those
test values for real encryption. Arabic, Chinese and emoji exercise byte-for-byte interoperability.
Native-platform unit interoperability is distinct from physical device export/restore acceptance.

## Remaining activation gates

Recovery-key presentation/storage, explicit user consent, picker permissions and temporary-file
cleanup, restore preview, recipient+sending archive coverage,
round-trip Android/iOS files, physical storage failure/restart tests, backup health and lost-key UX.
This backup profile does not select the live team encryption or device-key enrollment protocol.

Android account-wide snapshot reads use64-record keyset pages inside one Room transaction and
count exact escaped UTF-8 bytes before retaining each record. Encryption follows in memory;
the currently disabled API has no file provider or backup destination. This is not automatic cloud backup.
