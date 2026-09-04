# iOS device identity custody — inactive

Updated 2026-09-04. `TeamDeviceCustody` implements a local protected identity and
pending-proof state machine. It does not establish a current account session,
team membership, attestation, MLS identity or device authentication on each request.

## Native key and metadata policy

The production provider uses `SecureEnclave.P256.Signing.PrivateKey`, checks
availability and explicitly selects `WhenPasscodeSetThisDeviceOnly` plus
`privateKeyUsage`. There is no software-key fallback. CryptoKit's Data-signing
overload performs SHA256; the returned raw64 signature is locally verified against
the recorded P256 public key before it can escape custody.

Apple describes Secure Enclave keys as encoded, with no plaintext private-key
transfer and use restricted to the originating enclave. Its CryptoKit API offers
`dataRepresentation` for reconstruction. The implementation retains that opaque
representation, never software private-key bytes or a transferable archive key.
Sources: [Secure Enclave guidance](https://developer.apple.com/documentation/security/protecting-keys-with-the-secure-enclave),
[CryptoKit signing key](https://developer.apple.com/documentation/cryptokit/secureenclave/p256/signing/privatekey),
[explicit access control](https://developer.apple.com/documentation/cryptokit/secureenclave/p256/signing/privatekey/init(compactrepresentable:accesscontrol:authenticationcontext:)).

The separate generic-password item is service
`com.zaidsafa.pinbook.ios.team-device-custody.v1`, account `bounded-device-index`.
It uses the data-protection Keychain, passcode-set/device-only accessibility and
synchronization false. It does not modify personal backup, portable recovery or
account-session Keychain items. The device index and each record carry fresh
UUID generations; updates compare the SHA256 of the exact prior payload in
`kSecAttrGeneric` using one SecItemUpdate. The payload hash is a CAS selector and
consistency check, NOT encryption, a MAC, or defense against privileged rollback.

The protected value contains at most eight exact origin/account/authority-epoch
scopes, at most64KiB overall, and each opaque key representation is1..4096bytes.
Strict JSON validates the stored schema, phases, decoded keys, times, coordinates,
base64 spelling and uniqueness. The key provider must reconstruct the same public
key; missing, changed, malformed or unavailable keys fail instead of regenerating.
Only public metadata is returned in redacted snapshots; no sealed key, refresh
credential or raw challenge nonce appears in a snapshot or submission diagnostic.

Passcode removal deletes items protected by this accessibility class; they do not
migrate to a different device. Do not describe ThisDeviceOnly generally as proof
that every backup mechanism excludes an item. Loss/restore/retirement behavior must
be explained and physically accepted before activation.
[Apple accessibility policy](https://developer.apple.com/documentation/security/ksecattraccessiblewhenpasscodesetthisdeviceonly)

## Durable lifecycle

1. Explicit prepare commits RESERVED and a device ID before generating a key.
   READY atomically stores the winning opaque representation and public key.
   There is no separately permanent key alias to orphan. If concurrent candidates
   race, only one CAS can retain a key and none may sign before READY. A failed
   uncommitted candidate may be discarded; the reserved device ID stays unchanged.
2. Reopen uses the same retained identity. Eight retained scopes reject a ninth
   before key generation. No automatic scope deletion, replacement or key export.
3. Signing compares the exact current READY generation, canonical challenge,
   origin/account/epoch/device/key and access expiry. It commits SUBMIT_PENDING
   BEFORE invoking the signing provider. A failed or unknown commit/sign leaves
   uncertainty; no automatic proof retry. Concurrent owners cannot return two
   signatures for that READY generation.
4. Key use is followed by signature verification, fresh durable-generation and
   wall-clock/expiry checks. A late signer whose generation has been recovered
   cannot return a usable proof. Signed bytes remain the shared domain-separated
   enrollment message; no prehash, DER or arbitrary server-provided signing bytes.
5. Matching completion/lookup metadata records REGISTERED. An uncertain metadata
   write may already have committed and is reconciled by reopen; metadata itself
   grants no continuing remote authority. Exact key/device/account/epoch/enrollment
   matching prevents response confusion or replacement of a registered identity.
6. After the recorded proof deadline, recovery commits a fresh RECOVERING generation
   BEFORE a new exact-key lookup. Another recovery attempt gets another generation.
   A successful matching result can register; explicit current null returns READY
   with the SAME key/device ID. Lookup errors never become null. A registered record
   cannot be turned into READY by absence. No automatic challenge/signature retry.

The clock is wall time at this layer. Deadline passage does not prove server time
or absence of a late server commit. Stable identity and server uniqueness are still
required. The next coordinator must bind current account-session generation and
monotonic lifetime around custody/HTTP awaits, recheck after potentially slow reads,
retain unresolved ownership, and perform a fresh lookup even for local REGISTERED.
Session and device custody are separate transactions; a concurrent sign-out may
leave local device metadata but must prevent a successful account-bound flow.

## Evidence and limits

- Fifteen synthetic custody cases pass: consent/cap before keys, stable reopen,
  failed/unknown reservation/READY/pending/registered writes, key loss/replacement,
  corruption/protection downgrade, clock rollback/expiry, stale recovery, strict
  registration binding, cancellation, and two-owner READY/signing races. The
  production Keychain wrapper is exercised via an isolated in-memory SecItem API.
- A composed real localhost TLS test uses synthetic CryptoKit fixture keys and
  the actual onboarding transport. It checks lookup→challenge→complete, bearer
  handling, durable pending/registered state and verifies the exact raw64 signature
  captured from the transmitted body. The local server is a transport fixture,
  NOT the real registration service or a production TLS deployment.
- Full core **149/149 PASS**,13.156s:
  `/private/tmp/pinbook-ios-device-custody-composed-core.log`.
- Simulator build-for-testing **PASS**:
  `/private/tmp/pinbook-ios-device-custody-test-build.log`. No new app-host run,
  Secure Enclave generation, physical lock/passcode/restore acceptance or real
  Keychain capacity/CAS test is inferred from synthetic tests or compilation.
- Unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-device-custody-release.log`.

Native Secure Enclave protection and actual stored representation size require
physical-device acceptance. Unsupported hardware/no passcode must fail explicitly,
not downgrade. Retirement, bounded cleanup and key loss/reinstall UX remain required;
no permanent-eight-scope product limit is silently accepted as the final policy.
No normal navigation, real client/origin/epoch, shared infrastructure, phone,
signing/version, source push or TestFlight publication changed.
