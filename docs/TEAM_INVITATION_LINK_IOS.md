# Pinbook iOS invitation link grammar

Status: strict inbound and outbound routing implemented locally; production origin,
Associated Domains and AASA remain inactive pending Infrastructure approval.

`TeamInvitationLink` accepts an injected exact HTTPS origin and produces only:

`<origin>/join?invite=<token>`

The token must be exactly 43 canonical unpadded base64url characters decoding to
32 bytes. The complete URL is bounded to 1,024 printable ASCII bytes. Parsing
rejects HTTP, userinfo, origin paths, trailing slashes, fragments, redirects,
extra/duplicate query fields, alternate query-name encoding, changed case,
noncanonical token encoding and any URL that does not round-trip byte-for-byte.

Descriptions and reflection are redacted. The type does not log, persist or show
the capability token. It is ready for a later in-memory `ShareLink`, local QR
renderer and privacy-safe scanner. AppShell now accepts browser activities and
HTTPS URLs only through the injected router, then exposes the validated invitation
to the Team workspace without rendering its token. Disabled runtime stays closed.

See `TEAM_UNIVERSAL_LINKS_SETUP.md` for the opt-in entitlement and AASA deployment
artifacts. They are deliberately not selected by the current project build.

Focused tests: 2/2 pass using a synthetic `.example` fixture origin. Complete
Swift regression passes 384/384 and the unsigned Release iOS Simulator build
succeeds with unchanged production identity. No production domain, entitlement,
route, provider, device, TestFlight or server state changed.
