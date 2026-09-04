# iOS onboarding transport — inactive

Updated 2026-09-04. Implements the fourteen literal routes in Android/backend
`TEAM_ONBOARDING_HTTP_V1.md` alongside the six existing account routes. No deployed
origin, provider configuration, normal-navigation entry point or durable account,
device or membership authority is created by this layer.

## Contract and transport

`TeamOnboardingHTTP.swift` exposes internal typed invitation preview/claim,
device challenge/completion/lookup/revocation, team create/current/join and owner
invitation issue/list/revoke methods on the retained `TeamAuthHTTPClient`.
Public routes never attach a saved bearer. Protected routes require an active
snapshot with the exact configured origin and recheck its expiry after HTTP.
Clock rollback and unsafe time values reject. This snapshot check is not a fresh
durable session-generation check; the future coordinator must perform that too.

One client instance now retains a single unresolved request slot across ordinary
auth and onboarding. Concurrent calls fail busy; cancellation does not release the
slot until native URLSession invalidation settles. Independent client instances
do not share a global slot. The eventual host must inject the same retained client
into account and onboarding owners. There is no automatic retry or logout.

The existing fresh ephemeral URLSession, normal TLS validation, no cookies/cache/
ambient credentials, redirect refusal, one-use POST stream and 15-second resource
deadline remain. Responses are capped at 4 KiB actual/header-declared bytes except
invitation lists at 32 KiB and at most 100 unique entries. The old iOS auth limit
was 32 KiB; this deliberately narrows it to match Android's existing 4 KiB auth
policy. Google token responses retain their separate 32 KiB cap. Requests advertise
identity encoding and retain the 20,000-byte body limit.

Protocol JSON now rejects malformed UTF-8, BOM, decoded duplicate keys at any
depth, extra keys, more than four container levels, more than 2,048 value nodes,
noncanonical/fractional/exponent/unsafe integer tokens and wrong scalar types.
Boolean false cannot be supplied as numeric zero. This parser is also used by
the account-session wire codecs; financial/portable backup decoding is unchanged.

## Binding, consent and uncertainty

- `lookupInvitationAcceptance` adds protected `POST teams/acceptance` with exactly
  token/teamId/enrollmentId/role. The response is exactly `{membership:...}`.
  Only explicit JSON null on successful200 is eligible-pending at that check;
  missing/malformed fields, HTTP failures, expired access and foreign membership
  never become null. A non-null membership must match the account/team/enrollment/
  requested MEMBER or REVIEWER role and a nonnegative safe revision. Nested parsing
  retains strict duplicate-key/numeric checks, the shared unresolved client slot,
  ordinary4KiB cap and pre/post-response current-ticket expiry checks.
  This read-only lookup takes server locks; no polling or automatic retry. Null
  is NOT a reservation or proof a queued older accept cannot commit. Higher-level
  retry still needs original token supplied again, exact saved hash/account/team/
  enrollment/role, a durable attempt generation and NEW explicit consent. No raw
  token persistence, PENDING clearing or retry orchestration is added here.
- Invitation roles are MEMBER or REVIEWER; create-team must return OWNER. Join,
  issued invitations and membership responses must match the exact requested
  team/role/enrollment and current account. No email identity inference.
- Device challenge bytes reuse the existing canonical P256 builder. Locally
  known origin/account/session/epoch/device/key/expiry must match. Completion
  revalidates the prepared challenge before dispatch and accepts only raw64 proof
  shape; signature creation and verification belong to dedicated key custody.
- Registration responses must match the exact account/device/key/epoch. Only a
  successful exact `registration:null` result means current-key absence. An error,
  missing field, wrong type or mismatched record never becomes absence. Null does
  not establish absence of retained old-epoch records or authorize key rotation.
- No public invitation failure deletes an unrelated saved session. Response loss
  may follow a committed claim, join, registration or revocation; this layer
  cannot promise rollback and never automatically repeats the write.
- Claiming an account invitation, registering this device and joining a team
  remain distinct consent/ownership operations. Preview is not a reservation.
  Returned metadata alone is not lasting team access or proof of current rights.

## Evidence

- Fourteenth-route increment: six new intercepted tests plus one actual private
  localhostTLS case over success/pending/503/dropped-connection scenarios. Checks
  exact body/bearer, unchanged account custody, no persistence or automatic resend,
  malformed/foreign/nested-duplicate/unsafe-number responses,4096/4097-byte boundary,
  HTTP-error-vs-null, invalid input/origin/expiry/rollback and shared-slot cancellation.
  Focused onboarding **14/14 PASS**,0.255s:
  `/private/tmp/pinbook-ios-acceptance-route-focused.log`.
  Full core **222/222 PASS**,18.796s:
  `/private/tmp/pinbook-ios-acceptance-route-core.log`.
  Simulator build-for-testing and unsigned iPhone Release PASS:
  `/private/tmp/pinbook-ios-acceptance-route-test-build.log` and
  `/private/tmp/pinbook-ios-acceptance-route-release.log`. No new runtime acceptance.
  This TLS fixture tests transport shape, NOT deployed eligibility/DB-lock semantics.
  Earlier intermittentTLS failures remain open final-validation caveats.
- Four strict-JSON tests and eight intercepted onboarding tests pass, including
  all thirteen routes, exact fields/auth, role/account/device confusion, explicit
  null, strict false, duplicate list IDs, response caps, shared-slot cancellation,
  pre/post-response clock and expiry checks, and pre-dispatch proof revalidation.
- Two added real localhost TLS tests verify public/protected request bodies and
  bearer handling, a 100-entry list, lost responses/503 without automatic replay,
  and unchanged protected account custody. Only public synthetic fixtures are
  used; no provider, account, system trust-store change or real service.
- Full core **133/133 PASS** in 14.704 seconds:
  `/private/tmp/pinbook-ios-onboarding-final-core.log`.
- Simulator build-for-testing **PASS**:
  `/private/tmp/pinbook-ios-onboarding-final-test-build.log`. This is compilation,
  not a new app-host/UI run. Prior Apple/device/Google runtime gates remain open.
- Unsigned iPhone Release **PASS**:
  `/private/tmp/pinbook-ios-onboarding-final-release.log`. No signing, archive,
  version change or upload was performed.

Initial strict-JSON compile failed on a missing `try` and was corrected. Initial
full regression failed only because the old response-boundary test expected 32 KiB;
it now explicitly verifies 4,096 accepted / 4,097 rejected. Failed logs are retained
and not counted as passing evidence in VALIDATION.md.

## Next integration

Dedicated non-exportable device-key custody with bounded durable reservation and
generation-safe pending/recovery states, then a current-session/monotonic owner,
invited sign-in and explicit join UI. Android's corresponding custody and session-
bound registration contracts are read and recorded as cross-platform guidance,
not proof of iOS Keychain or hardware behavior. Owner now requires keeping tasks
separate; do not send cross-task GUI/status messages. Runtime verification must use
isolated Pinbook resources without disrupting another task. Physical protection/provider checks,
trusted epoch/origin/client setup, retirement/deletion/retention, MLS and real
staging remain separate gates. Build 0.1.0 (3) stays unchanged; no interim upload.
