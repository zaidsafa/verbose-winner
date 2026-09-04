# Native sign-in and MLS feasibility — research only

Checked September 4, 2026. No dependency, provider, credential, backend, release or
runtime change. TestFlight build 3 remains published with team functionality disabled.
Login-provider choice is pending the owner; this is not a decision to adopt OIDC.

## Google iOS nonce: supported, not a browser-only blocker

GoogleSignIn-iOS 9.0.0 added caller-provided nonce support. The pinned **9.2.0**
public header exposes `signInWithPresentingViewController:hint:additionalScopes:
nonce:completion:` and the variant also accepting claims. This is interactive
sign-in; do not treat a cached `restorePreviousSignIn` token as proof of a newly
issued server challenge. The hosted class reference omits this overload, so prefer
the exact tagged header for API verification. No SDK was installed or tested here.

Sources: [9.0.0 release](https://github.com/google/GoogleSignIn-iOS/releases/tag/9.0.0),
[9.2.0 header](https://raw.githubusercontent.com/google/GoogleSignIn-iOS/9.2.0/GoogleSignIn/Sources/Public/GoogleSignIn/GIDSignIn.h).

The release list now shows 10.0.0, with dependency/deployment changes; this review
does not approve upgrading blindly or claim local Xcode integration compatibility.
[Release history](https://github.com/google/GoogleSignIn-iOS/releases).

Google's native authorization-code flow supports S256 PKCE. An external system
authentication session through maintained AppAuth is another feasible approach;
do not use an embedded WKWebView. Register the correct native client and redirect.
PKCE protects code exchange; it does not replace the backend's one-use OIDC nonce.
Sources: [Google native flow](https://developers.google.com/identity/protocols/oauth2/native-app),
[RFC 8252](https://www.rfc-editor.org/rfc/rfc8252).

Pinbook integration requirements (proposal): fresh server challenge, bounded
expiry, exact selected audience and trusted issuer, verified signature/algorithm,
issuer-plus-subject account mapping, atomic nonce consumption, and post-await time
rechecks. Configure the server client ID for backend audience rather than accepting
arbitrary audience lists. A Google ID token proves identity only; membership,
device enrollment and Pinbook session issuance remain separate. Never accept a
personal Drive access token, client-asserted user ID, or email as team API authority.
[Google backend authentication](https://developers.google.com/identity/sign-in/ios/backend-auth).

## MLS candidates

Follow-up: `OPENMLS_AUDIT_ADOPTION_20260904.md` supersedes this short review's
unverified audit mapping below. It verifies the full report, exact scope/commit,
public fix ancestry, unclosed storage gap and newer 0.9.0 security advisories.

| Candidate | Verified evidence | Decision boundary |
| --- | --- | --- |
| OpenMLS | RFC 9420 Rust implementation, MIT; iOS/Android targets explicitly built in CI but unsupported and not runtime-tested there. Maintainers prohibit no features automatically: content-debug and crypto-debug can expose plaintext/keys. | Strong candidate for an isolated interoperability spike, not approved for production mobile. Freeze exact crate/provider/transitive versions and prohibit sensitive debug features. |
| mls-rs | Apache-2.0 or MIT; repository includes FFI/UniFFI and CryptoKit provider. README explicitly says no full third-party security audit yet. | No evidence to call this the better audited replacement. A successful dependency-audit CI job is not a protocol audit. |
| Wire CoreCrypto | Rust with Swift/iOS and Kotlin/Android binding/build/test paths, using Wire's OpenMLS fork; GPL licensing documented. | More integrated mobile reference, but not a drop-in approved dependency. Verify exact license/distribution obligations and fork/audit scope before adoption. No commercial/legal suitability claim. |

Sources: [OpenMLS repository](https://github.com/openmls/openmls),
[mls-rs repository](https://github.com/awslabs/mls-rs),
[Wire CoreCrypto repository](https://github.com/wireapp/core-crypto),
[Wire CoreCrypto documentation](https://wireapp-core-crypto-74.mintlify.app/).

OpenMLS audit status is meaningful but version-scoped: the maintainers' May 27,
2026 announcement reports SRLabs found eight issues, one high, with seven fixed
and one low still being addressed at that publication date. It must not be reported
as zero outstanding findings today without checking remediation. The August 25
announcement describes 0.9.0, which is not automatically covered by an older audit.
The announcement uses abbreviated version numbers; do not infer an audited commit
from them. **Full-report commit/scope mapping and current low-finding disposition
were not verified in this short review**, and remain explicit adoption gates.
Sources: [Maintainer audit announcement and report link](https://blog.phnx.im/openmls-independent-security-audit/),
[OpenMLS release/audit posts](https://blog.openmls.tech/).

## Thirty-day delivery expiry and recovery

RFC 9420 has ordered state transitions and bounded delayed-message policies, not
Pinbook's thirty-day product retention rule. It calls for limits on retained
unused message keys and ratchet advancement. New application messages must use
the state after relevant membership changes. [RFC 9420 sections 14–15](https://www.rfc-editor.org/rfc/rfc9420.html#section-14).

Consequent Pinbook design requirements, not already implemented guarantees:

- Treat handshake/commit sequencing separately from temporary payload lifetime.
  If an offline member misses required history beyond retention, detect the gap;
  do not silently skip epochs. Require authorized fresh enrollment/rejoin or
  another reviewed recovery procedure before sending again.
- Rejoining a current epoch must not resurrect expired payloads or revoked access.
  Keep received-note archives separate from live MLS state. Restoring the portable
  JWE archive must not restore membership, ratchets, KeyPackages or ACK authority.
- Do not clone/roll back active cryptographic state across devices or backup
  restores. Review key reuse, replay and fork hazards. Membership change, commit
  acceptance, durable local state and transmission must have explicit crash-safe
  ordering and idempotent recovery.
- A device with decrypted saved content cannot be made to forget it by server
  expiry. State clearly what deletion and forward-secrecy guarantees cover.

## Smallest useful next gate

Do not activate or implement a home-grown group protocol. First complete the
exact audit/patch/license matrix and choose one library/provider pair. Then an
isolated test-only Rust/Swift/Kotlin harness should cover add/remove, ordered
commits, offline catch-up and forced rejoin, wrong identity, rollback/replay,
concurrent commits, persistence failures, and no content/key logging. Audit the
Pinbook-specific authentication, state-storage and recovery integration separately.
No real accounts, public service, provider setup or new dependency is authorized
by this research note itself.
