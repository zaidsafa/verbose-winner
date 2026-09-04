# Native sign-in and MLS feasibility — research only

Checked September 4, 2026. No dependency, provider, credential, backend, release or
runtime change. TestFlight build 3 remains published with team functionality disabled.
The original provider-pending note is superseded by the decision context below.

## Provider direction accepted during continuous-work continuation

In iOS task `01a05c65-fc6a-79b3-99a4-2cc3994b78cf`, the assistant's status response
ended with: "One decision remains: may I use Apple and Google sign-in for team
accounts? There is still engineering work beyond that choice."

The owner's immediately following request was: "proceed towards the goal , don't
stop until i ask you to. deploy your whole potential".

The iOS task interprets that direct question/response as approval of its proposed
Apple+Google pilot sign-in direction. It explicitly told the owner: "I'm treating
your 'proceed' as approval for the Apple and Google sign-in option I proposed. I'll
coordinate that with the Android task; connecting an account will remain an
explicit choice inside the app." Android was notified and accepted proceeding
with implementation/contract preparation on this stated basis. Do not repeat the
provider-choice question or claim that the owner supplied client IDs or credentials.

This is a provider direction, not authorization for shared Infrastructure changes,
unverified OAuth console settings, automatic user account connections, invented
review accounts, MLS adoption or premature team activation. Real client identifiers,
redirects/entitlements, server validation/enrollment and security gates remain open.

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

Fresh tagged-source review during refresh integration confirms an isolation issue
to resolve before adoption: GoogleSignIn uses sharedInstance, and its interactive
method replaces saved sign-in state/currentUser in the SDK's Keychain. A future
personal Drive account must not be accidentally replaced or globally signed out by
team identity cleanup. This is a source-level integration concern, not an observed
user-data failure. A maintained AppAuth system-session flow with explicit account
selection/nonce and only volatile provider results is being compared; no SDK has
yet been installed and no provider is contacted. The9.2.0 package declares Swift6,
iOS12 minimum and dependencies including AppAuth2.1+, AppCheck11+ and GTMAppAuth5+.
Dependency/privacy/pinning/build acceptance remains required before adoption.
[Tagged package](https://raw.githubusercontent.com/google/GoogleSignIn-iOS/9.2.0/Package.swift).

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

## Native contract follow-up: September 4

Android's `login-proof.mjs` now distinguishes the exact trusted backend audience
from the native authorized presenter. Source review at SHA256
`a9207772042de1ea0710379cc17a8d84ffcc73a8947d11b7ec3537ea1243ef15`
found that distinct presenters require a signed exact `azp`; only explicitly
configured Google profiles accept its documented bare issuer spelling. Google
9.2.0 source passes caller nonce unchanged into AppAuth and sends serverClientID
separately as audience. This supports the proposed interface, not proof of real
native ID-token claim shape or SDK integration.
[Tagged source](https://raw.githubusercontent.com/google/GoogleSignIn-iOS/9.2.0/GoogleSignIn/Sources/GIDSignIn.m),
[Google claims](https://developers.google.com/identity/openid-connect/openid-connect#an-id-tokens-payload).

Apple's installed SDK exposes request nonce/state and a returned credential state.
Use the exact raw server nonce with fresh local callback state; do not introduce
Firebase-style nonce hashing into this direct backend profile. Native app audience,
issuer and real provider configuration must be explicitly verified before serving.
[Apple request nonce](https://developer.apple.com/documentation/authenticationservices/asauthorizationopenidrequest/nonce).

Android's local account-session slice at `93e4314` adds actual PostgreSQL admission
and opaque access/refresh rotation; routes remain unfrozen and no provider is live.
Native clients must serialize refresh and durably mark it in-flight BEFORE sending,
then atomically replace the token pair and clear that marker. Process death, lost
response or persistence failure requires reauthentication, not retry of the old
refresh token (which can revoke a committed successor). Credentials stay outside
portable/device/cloud backups. Admission and sessions are not team/device authority.
The external restore authority gate, actual provider setup and session transport
remain open. Android owns its backend; no source or runtime mutation was made there.

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
