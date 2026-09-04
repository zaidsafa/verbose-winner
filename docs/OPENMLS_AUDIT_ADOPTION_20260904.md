# OpenMLS audit and adoption gate

Checked September 4, 2026. Research only: no Rust dependency, provider, network
service or group encryption installed/enabled. No TestFlight upload.

## Audited scope versus candidate

SRLabs report v1.2 (March 11, 2026), printed pages 8, 12 and 17-27, reviews
`openmls`, `traits` and `basic_credential` through commit
`a3402f2c967533d5000d16016ef6a7c043e5a989` (October 22, 2025). Crypto/storage
providers, example client and delivery service are excluded. Therefore this
report establishes **no audited crypto-provider version**.
[Full report](https://blog.openmls.tech/SRL-OpenMLS_security_assurance_assessment.pdf).

Local source PDF SHA256:
`791eec15208055ac8b7f7268c606a3ee0b974eb184f6a7a181b2f1d854c38647`.

| Component | Manifest at audit commit | Candidate release manifest |
| --- | --- | --- |
| openmls | 0.7.1 | 0.9.0 |
| openmls_traits | 0.4.1 | 0.6.0 |
| openmls_basic_credential | 0.4.1 | 0.6.0 |
| openmls_rust_crypto (excluded) | 0.4.1 | 0.6.0 |
| openmls_libcrux_crypto (excluded) | 0.2.1 | 0.4.0 |

Audit manifest versions identify the reviewed development snapshot, not equivalence
to the published 0.7.1 tarball. No root Cargo.lock exists at that commit; original
resolved transitive versions cannot be reconstructed from these manifests alone.
[Audited tree](https://github.com/openmls/openmls/tree/a3402f2c967533d5000d16016ef6a7c043e5a989).

Candidate tag `openmls-v0.9.0` resolves to
`3a3e35de3feeca8f6605143c464d5452ae584d43`, August 25, 2026. Its checked-in lockfile
contains hpke-rs/crypto/libcrux/rust-crypto 0.7.0, libcrux-aead/chacha20poly1305/
ed25519 0.0.9 and tls_codec 0.5.0. These are upstream workspace resolutions,
not a Pinbook lockfile or provider audit. The RustCrypto manifest explicitly
enables hpke-rs-rust-crypto's `experimental` feature; assess supported suites
and selected feature reachability before choosing a provider.
[Candidate tree](https://github.com/openmls/openmls/tree/3a3e35de3feeca8f6605143c464d5452ae584d43),
[lockfile](https://github.com/openmls/openmls/blob/3a3e35de3feeca8f6605143c464d5452ae584d43/Cargo.lock),
[RustCrypto manifest](https://github.com/openmls/openmls/blob/3a3e35de3feeca8f6605143c464d5452ae584d43/openmls_rust_crypto/Cargo.toml).

## Eight findings and public remediation evidence

Table 9 has six Mitigated, one Acknowledged, one Risk Accepted. Do not flatten
that into eight fixes or seven code fixes. The later May announcement says seven
addressed and one low outstanding; it is less precise about the accepted risk.
[Announcement](https://blog.phnx.im/openmls-independent-security-audit/).

| ID / severity | Problem (paraphrased) | Report status | Public mapping |
| --- | --- | --- | --- |
| S3-7 High | Short MAC accepted | Mitigated | [GHSA-8x3w-qj7j-gqhf](https://github.com/openmls/openmls/security/advisories/GHSA-8x3w-qj7j-gqhf): patched 0.7.2 / 0.8.0. |
| S2-5 Medium | Existing group overwritten | Mitigated | [PR 1929](https://github.com/openmls/openmls/pull/1929), default collision refusal. |
| S2-2 Medium | Wrong historical credential | Mitigated | [PR 1944](https://github.com/openmls/openmls/pull/1944), corrected past-epoch lookup. |
| S2-6 Medium | Incomplete join capability checks | Mitigated | [PR 1933](https://github.com/openmls/openmls/pull/1933), creation.rs adds all-context-extension check. |
| S1-4 Low | Validation documentation mismatch | Mitigated | PR 1933 updates validation code/documentation. |
| S1-3 Low | Memory/disk divergence after write failure | Acknowledged | Related [PR 1935](https://github.com/openmls/openmls/pull/1935) remains open, unmerged proof of concept. No verified closure. |
| S0-1 Info | Excessive allocations | Risk Accepted | Application input bounds required; not a demonstrated upstream code fix. |
| S0-8 Info | Removed members overvalidated | Mitigated | [PR 1943](https://github.com/openmls/openmls/pull/1943). |

GitHub API ancestry checks place each following merged fix in the candidate's
history (`merge_base == fix`, behind_by 0). Mapping is based on public diffs and
report descriptions; the private audit tracker itself was not accessed.

- PR1929: `a50360936640921ece7bae7096607fd9b9f389d4`
- PR1944: `26eaa4d0e4ddc09cc5fa168b18fe8e2eb09ef628`
- PR1933: `b91ec12dae25b4c4d16f221d134c26cf926bffc5`
- PR1943: `0ee014af596c5c8f0793a19fb31ec4e762ce4b30`

PR1933's join-specific negative test was explicitly ignored because generating
its invalid fixture required bypassing an earlier validation. Do not claim every
new upstream regression executes or that we ran upstream tests. A Pinbook spike
must exercise invalid Welcome input without disabling production validation.

## Newer release risks

Do not adopt 0.8.1 merely because it was named in the audit announcement. Two
August advisories affect releases below 0.9.0: pre-authentication quadratic
extension processing and a byte-decoder bounds panic. Both identify 0.9.0 as
patched. These are distinct from the report's accepted allocation risk.
[GHSA-w62v-gv48-63rh](https://github.com/openmls/openmls/security/advisories/GHSA-w62v-gv48-63rh),
[GHSA-rrmv-c79f-cf5r](https://github.com/openmls/openmls/security/advisories/GHSA-rrmv-c79f-cf5r).

The candidate also changes storage compatibility and raises MSRV to Rust 1.91.
Upstream mobile targets remain build-only/unsupported: a tagged release is not
supported production iOS/Android integration. Sensitive debug and draft features
must remain disabled, and dependency/feature/license checks remain required.
[Changelog](https://github.com/openmls/openmls/blob/3a3e35de3feeca8f6605143c464d5452ae584d43/CHANGELOG.md),
[README](https://github.com/openmls/openmls/blob/3a3e35de3feeca8f6605143c464d5452ae584d43/README.md).

## Pinbook adoption / spike matrix (not implemented)

| Gate | Smallest useful proof | Current decision |
| --- | --- | --- |
| Library/provider | Pin exact 0.9.0 source, provider, transitive lock and baseline ciphersuite; review provider assurance separately. | Research candidate only; no production adoption. |
| Mobile boundary | Real Swift/Kotlin FFI compilation, cancellation/lifetime/error handling and synthetic interoperability. | Not run; no dependency installed. |
| Atomic state | Serialize group operations; transactional store, discard mutated object after failure and reload committed state. Send only after durable commit; inject errors at each write. | S1-3 remains an integration blocker. DB rollback alone cannot undo a Rust object's mutation. |
| Input resources | Enforce ciphertext and decoded collection limits before allocation; malformed input/fuzz and CPU/memory bounds. | Accepted upstream risk is not accepted by Pinbook automatically. |
| Membership | Bind verified account/device/enrollment to credential; remove/rekey/rejoin; reject stale members and commits. | Provider selection/session/enrollment not enabled. |
| Thirty-day delivery | Offline ordered-commit catch-up or explicit authorized rejoin; no silent epoch skip, no expired content resurrection. | Required tests, not an MLS-provided retention guarantee. |
| Recovery | Portable note archive separate from active ratchets/keys/membership; never clone live state through backup. | Existing JWE archive restores received text only. |
| Release | Cross-platform complete workflow, provider/storage review, isolated staging admission and final acceptance. | Hold all interim TestFlight uploads; no production approval. |

Conclusion: finish the selected-provider and crash-safe integration design before
a test-only spike. This review narrows the candidate and identifies gaps; it does
not certify OpenMLS or Pinbook cryptography and does not authorize deployment.
