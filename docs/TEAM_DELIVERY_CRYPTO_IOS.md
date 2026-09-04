# Team delivery cryptographic primitives for iOS — inactive

Updated September 5, 2026 for parity with Android checkpoint `4b30718`.
`TeamDeliveryCryptoPrimitives` provides only the two reviewed standard building
blocks proposed for a future multi-recipient text envelope:

- RFC 7518 ECDH-ES Concat KDF with SHA-256; and
- RFC 3394 AES Key Wrap using a 256-bit key-encryption key.

Concat KDF accepts a 1...132-byte shared secret, a 1...64-byte printable ASCII
algorithm identifier, party values up to 512 bytes each and only 128/192/256-bit
output. The delivery profile is `ECDH-ES+A256KW`. Key wrap accepts exactly a
256-bit KEK and a key of at least 16 bytes in 8-byte blocks. Unwrap rejects a bad
integrity value. Temporary app-owned construction buffers are cleared on exit.

Tests match RFC 7518 Appendix C and RFC 3394 section 4.6 exactly. Independent
CryptoKit P-256 parties derive the same KEK and complete wrap/unwrap; changed
wrapped bytes and unsupported bounds fail closed.

The later agreement-possession contract also reuses the reviewed Concat KDF shape
with algorithm `pinbook-agreement-confirm-v1`, PartyU challenge ID and PartyV
agreement-key thumbprint. Its byte-identical Android/server vector and physical
Secure Enclave evidence are documented separately in
`TEAM_AGREEMENT_ENROLLMENT_IOS.md`.

This is not an envelope, note encryption, key generation/custody, registration,
network operation or sync activation. The protected header and recipient envelope
remain unfrozen.
