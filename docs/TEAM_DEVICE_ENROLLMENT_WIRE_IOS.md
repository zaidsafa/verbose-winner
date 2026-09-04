# Device enrollment wire interoperability — inactive

Implements the existing backend contract from Android checkpoint a629647e,
`docs/TEAM_DEVICE_ENROLLMENT.md` and `server/src/device-enrollment.mjs`.
No service routes, database work or native enrollment authority are added.

Read-only backend verification used checkout0082c7cb, with unchanged serializer
SHA256 `79c1b5e945bf81a2a93702bf6a8190bd28bdfcced290b7085a0b5e82e98ae80f`.
Contract SHA256 `a0abcea46683e1682d5c03610ff360b5d924ee21db436f7910a0b00d677d4a76`.

`TeamDeviceEnrollmentWire` is internal. It validates exact public P256 JWK members,
canonical coordinates and the actual curve point; computes the RFC7638 thumbprint;
and constructs the exact domain-separated UTF8 JSON array only after checking local
origin, epoch, account, session, device, key and access-expiry bindings. The response
cannot choose a destination or supply arbitrary bytes to sign. Message serialization
uses no whitespace/newline and deliberately does not escape HTTPS slashes.

The backend audience is a canonical HTTPS origin without a trailing slash. The
existing session scope normalizes a path and must not be copied verbatim into this
field. Alternate spellings, URL credentials, paths, IP addresses and default-port
spellings are rejected. Production trusted-origin/epoch provisioning remains open.

The public fixture `Tests/PinbookCoreTests/Fixtures/team-device-enrollment-v1.json`
was generated with an ephemeral Node P256 key. Only the public JWK, synthetic
challenge, exact message and raw64 signature were retained. Private key discarded;
these public values are never an admitted account or a device credential.

Tests cover Node signature verification by CryptoKit, exact bytes/thumbprint,
all local binding mismatches, changed signed fields, malformed/off-curve/private
keys, bounds/expiry, canonical origins, DER rejection and double-hash mismatch.
A fresh CryptoKit key/signature test can emit a PUBLIC-ONLY vector with the explicit
`PINBOOK_PUBLIC_WIRE_VECTOR=1` test environment variable, for reverse Node verification.
No private key or provider/session token is printed or written.

The retained reverse fixture is `team-device-enrollment-swift-v1.json`. Reproduce
verification against the real local backend serializer (read-only, no service/DB
initialization) with:

```sh
node scripts/verify-device-enrollment.mjs '/Users/zaidsmac/Documents/ChatGPT/TC Projects/pinbook-team-delivery'
```

Both directions passed exact bytes/thumbprint/raw-signature verification and all
nine individual field-mutation negatives. The script additionally checks newline
and double-hash mismatches. These vectors are interoperability tests, not audited
key-custody or real-account acceptance.

## Physical Android QA public vector — September 5

The Android task supplied `shared/team-device-enrollment-android-qa-v1.json`,
reporting generation by its physical Samsung AndroidKeyStore QA test and deletion
of the ephemeral private alias afterward. Only public JWK, synthetic bindings,
canonical bytes and raw64 signature are in this fixture. Its copied iOS test
resource has the exact same SHA256:
`bebd7e86c612c42edf117a5076e27773e61b7806b69f94cffdfa4fd25b6cf603`.

Swift/CryptoKit **7/7 focused tests PASS**,0.017s, including the exact new Android
vector: canonical bytes/thumbprint/raw signature and public JWK round trip;
rejection of changed local bindings, challenge/nonce/expiry, appended newline,
DER-as-raw and double hashing. Log:
`/private/tmp/pinbook-ios-android-qa-wire-20260905.log`.
Physical iPhone16Pro/iOS26.6.1 execution now also **PASS**,0.001s for this exact
Android-vector test; complete latest app-host suite **273/273 PASS**,8.533s, zero
skips/failures. Result:
`/private/tmp/Pinbook-QA-Physical-Android-Vector-20260905.xcresult`;
log: `/private/tmp/pinbook-qa-physical-android-vector-20260905.log`.
The20-test UI suite passed immediately before this test-only fixture addition;
it was not repeated after that rebuild. This proves
compatibility of these bytes, not attestation of their origin, live enrollment,
provider admission, reviewed MLS or notes delivery.

This is not a complete activated signer/enrollment flow. Integration still needs
the implemented custody/generation/operation owners and HTTP routes connected to
trusted epoch/configuration, uncertain-finish and revocation/replacement UX,
complete physical key-lifecycle checks and server/Infrastructure admission. Do not import
archive keys or restore device authority from backup. A current-epoch lookup null
does not establish that an older-epoch registration row or quota reservation is absent.
See VALIDATION.md for executed evidence; compilation is not runtime acceptance.
