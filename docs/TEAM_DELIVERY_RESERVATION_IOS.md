# Authenticated team-delivery reservation on iOS

## Accepted shared contract

This local iOS checkpoint matches Android/server commits
`6ac3ba802ab637ceb9eb9be7ecf8f424512f47e3` and
`52f35617a691f27fafbde9ba6ab1a26e319acda3`.

- Challenge: `deliveries/submit/challenge`
- Reservation: `deliveries/submit/reserve`
- Proof: the current account, session, device, enrollment, team, delivery ID and
  canonical submit-intent SHA-256 are signed by the registered device key.
- Submission: the exact canonical intent plus its exact canonical multi-recipient
  JWE. The JWE audience, byte count and lowercase SHA-256 must match the intent.
- Response: exactly 11 reservation fields and exact four-field frozen targets;
  unexpected, missing, malformed or differently ordered data is rejected.
- Limits: ordinary authenticated requests remain capped at 20,000 bytes; only the
  reservation request and response use the independently bounded 140,000-byte cap.

The reservation must preserve the signed delivery ID, membership revision,
audience digest, intent hash, JWE hash/size, object ID and sorted frozen audience.
Its lifetime must be positive, unexpired when received and no longer than 15
minutes. All ten server lifecycle states are parsed exactly.

## Saturation and retry rule

Server `429 capacity` means retry later. This boundary performs one request only:
it does not retry automatically and never creates a replacement delivery ID. A
later owner must retry the same durable delivery identity after re-establishing
fresh authorization and challenge state.

## Deliberate inactive boundary

This code does not activate a sender coordinator, provider/object write, journal,
normal app UI, server origin, Google Drive, physical-device sync or TestFlight.
Those require their own integration and acceptance gates. The sender-side JWE
validation is structural and audience-bound; it does not decrypt and does not
prove current recipient private-key possession.

## Acceptance evidence

- Reservation/crypto models: 8/8 passed in
  `/private/tmp/Pinbook-Delivery-Reservation-Focused-Retry-20260905.xcresult`.
- Complete authenticated transport suite: 23/23 passed in
  `/private/tmp/Pinbook-Delivery-Reservation-HTTP-Acceptance-20260905.xcresult`.
- Fresh DerivedData now resolves app-host and UI tests only as iPhone/iPad targets;
  Mac Catalyst remains disabled for those test bundles.
- Complete exact-current app-host run executed 447 tests: **442 passed**, **4
  expected physical-only skips**, and one existing native Files picker case hit a
  Simulator dismissal timing failure. That exact case then passed **1/1** on a
  clean isolated retry. Evidence:
  `/private/tmp/Pinbook-Delivery-Reservation-Full-AppHost-20260905.xcresult` and
  `/private/tmp/Pinbook-Delivery-Reservation-Native-Files-Retry-20260905.xcresult`.
- Unsigned production iPhone Release compiled successfully with unchanged bundle
  `com.zaidsafa.pinbook.ios`, version `0.1.0`, build `3`.
