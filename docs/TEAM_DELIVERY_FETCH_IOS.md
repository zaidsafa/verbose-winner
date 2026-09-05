# Inactive authenticated delivery fetch checkpoint

Updated: 2026-09-05 (Asia/Shanghai)

## Frozen source contract

This checkpoint matches Android/server commit
`f11f6383665bb1489fb402272302137ef4c683f6`. It is deliberately default-off and
adds no production origin, provider, background task, retry loop, navigation or
TestFlight behavior.

- The exact canonical signed request body is
  `{"deliveryId":"<id>","type":"pinbook-delivery-fetch-v1"}`.
- Challenge dispatch is isolated to `POST /api/v1/deliveries/challenge` with the
  exact enrollment ID and `delivery-fetch` binding.
- Ciphertext fetch is isolated to `POST /api/v1/deliveries/fetch` with the exact
  challenge ID, raw P-256 signature and canonical body, all base64url encoded.
- The existing device-request message binds the current account session, device,
  enrollment, authority epoch, team, delivery ID, body hash and access expiry.
- The client revalidates the signature before dispatch and rechecks the access
  ticket after the response. There is no automatic retry.
- The response must contain exactly `deliveryId`, `acceptedAt`, `expiresAt`,
  `jweBytes`, `jweSha256` and `jwe`. The delivery ID must match the signed request;
  expiry must equal acceptance plus 30 days; base64url must be canonical; and the
  decoded encrypted bytes, declared size and lowercase SHA-256 must match.
- Decoded JWE bytes are limited to 1...100,000 bytes. The complete HTTP response
  is independently capped at 140,000 bytes, allowing the canonical base64url
  envelope while rejecting larger responses before parsing.

## Evidence

- Production source compiled for iOS Simulator with signing disabled.
- The complete `TeamOnboardingHTTPTests` suite passed **21/21** on iOS 26.5 Simulator,
  including three new fetch cases for exact routes/canonical proof, a 70,000-byte
  encrypted payload, malformed/confused/oversized responses, invalid signatures,
  and access expiry after reply:
  `/private/tmp/Pinbook-Delivery-Fetch-Contract-Final-20260905.xcresult`.
- The complete exact-current signed Simulator app-host regression passed
  **408 + 4 expected physical-only skips** (412 total), zero failures:
  `/private/tmp/Pinbook-Delivery-Fetch-Full-AppHost-20260905.xcresult`.
- The unsigned production Release build passed with unchanged bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`.

## Explicit non-claims

This is an authenticated encrypted-byte retrieval boundary, not a team inbox or
completed sync feature. It does not decrypt, archive, acknowledge, reconcile or
display a delivery. It does not prove server deployment, provider behavior,
Android-to-iOS delivery, revocation under real infrastructure or production UI.
Those remain gated by a later reviewed coordinator and isolated staging evidence.
