# Current team audience lookup for iOS — inactive

Updated September 5, 2026 to match Android owner checkpoint `f954b56` and the
corrected shared request contract `dbeba7df0d64a637ea89fa2614cbe0b4fbeae97b`.
This is a one-flight foreground authority lookup. It is not live note sync and is
not reachable from the normal app.

## Exact ownership

`TeamAudienceLookup` retains one reviewed account generation and derives one
exact device scope from its origin, account and authority epoch. Each explicit
lookup:

- rejects overlap and never retries, caches, polls or starts background work;
- requires a fresh local `REGISTERED` device with the requested enrollment;
- checks the exact current account and device generations around every await;
- confirms the same enrollment and signing-key thumbprint from the server;
- fetches a fresh current membership revision for the requested team;
- creates one random 32-byte request ID and obtains one typed audience challenge;
- signs only the locally rebuilt canonical message with the retained registration
  key, while checking account authority inside the custody transaction;
- executes once, then revalidates the returned team, revision and every target.

The audience remains bounded to nine other accounts. Account, device and
enrollment identifiers must each be unique. Every target must now contain
distinct signing and agreement P-256 JWKs matching their RFC7638 thumbprints;
missing agreement credentials fail the entire lookup rather than silently
shrinking it. Wall time, monotonic time, access expiry and proof expiry are checked
before and after remote and custody boundaries.

Cancellation marks the retained operation invalid and requests cancellation, but
the one-flight slot is not released until even a noncooperative dependency has
settled. A late result therefore cannot overlap with a second authority request.

## Custody boundary

`TeamDeviceCustody.signRequest` is a read-only operation on one exact registered
generation. It verifies binding, enrollment and key identity, runs the supplied
account check before and after signing, validates the raw 64-byte P-256 signature
locally and writes no device metadata. It does not export the sealed private key.

## Evidence and remaining boundary

Focused lookup and custody tests are **6/6 PASS**; complete core is **293/293
PASS**. Physical-iPhone lookup is **5/5 PASS**, custody is **16/16 PASS**, and the
complete app-host suite is **320/320 PASS**, with zero failures or skips. Signed
isolated QA and ordinary unsigned Release builds pass, and QA returned to a normal
launch. Exact artifacts and corrected build attempts are listed in
`VALIDATION.md`.

Transport tests are intercepted and identities are synthetic. No live endpoint,
provider login, recipient trust, encryption envelope, durable submit/fetch,
archive-before-ACK, Android/iPhone note sync, production route, release archive or
TestFlight update was added. The next safe layer is the reviewed shared crypto
primitive and a separate agreement-key custody identity; signing-key reuse is
forbidden and the delivery envelope remains unfrozen.
