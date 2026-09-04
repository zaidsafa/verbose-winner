# iOS delivery agreement-key custody — inactive

Updated September 5, 2026 for parity with Android checkpoint `10f3141`.
Pinbook now has a dedicated P-256 ECDH identity for future encrypted team
delivery. It is never the existing P-256 signing identity.

The deterministic scope hashes the exact purpose, canonical origin, account,
authority epoch and enrollment; raw identifiers are not used as the Keychain
account. Creation is explicit. Read-only `current()` never creates. Keychain add
is atomic, synchronizable is false, and accessibility is
`WhenPasscodeSetThisDeviceOnly`. There is no update, delete, replace, export,
software fallback or signing operation. An ambiguous add adopts only an exact
readable winner for the same scope.

The production provider uses `SecureEnclave.P256.KeyAgreement.PrivateKey` with
private-key usage access control. Its opaque representation is bounded and can
only reopen the same Secure Enclave identity. Peer JWK and RFC 7638 thumbprint are
checked before agreement. The 32-byte shared secret feeds the reviewed RFC 7518
Concat KDF and is cleared before return. The caller owns and must clear the
returned KEK. Supplied current-access authority is checked before and after key
operations, and the retained exact key is revalidated before a result escapes.

Synthetic custody plus standard primitives pass **9/9** focused and **302/302**
complete core tests. In the isolated QA app, the actual Secure Enclave identity
was created/reopened through the QA Keychain and derived the same KEK as an
independent software peer; A256 wrap/unwrap completed. The complete physical
app-host suite is **330/330 PASS**. Exact evidence is in `VALIDATION.md`.

No normal route constructs this custody. The separate inactive signed enrollment
coordinator and required audience fields now exist in source; see
`TEAM_AGREEMENT_ENROLLMENT_IOS.md`. They do not make this usable encryption or
live Android/iPhone sync. ECDH key confirmation, the canonical envelope and
delivery remain separate gates.
