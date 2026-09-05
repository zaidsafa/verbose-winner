# Team invitation Universal Links setup

Status: source-complete, production default-off.

The app now routes `NSUserActivityTypeBrowsingWeb` and HTTPS URLs through the
injected `TeamWorkspaceInvitationRouter`. Disabled production runtime accepts no
invitation. Enabled runtime accepts only the exact configured HTTPS origin and
canonical `/join?invite=<43-character-token>` grammar; alternate hosts, paths,
queries, fragments and encodings remain closed.

Infrastructure must complete these steps before an archive may enable the
capability:

1. Copy `Config/TeamWorkspace.opt-in.xcconfig` into the final archive invocation.
2. Create ignored `Config/TeamWorkspace.xcconfig.local` containing only:
   `PINBOOK_TEAM_INVITATION_HOST = <approved-host>`.
3. Add Associated Domains to the registered App ID and regenerated provisioning
   profile. The opt-in xcconfig selects `Config/PinbookTeamUniversalLinks.entitlements`.
4. Generate the exact file with
   `Scripts/generate-team-aasa.sh APPLE_TEAM_ID APP_BUNDLE_ID OUTPUT_PATH`, publish it as
   `https://<approved-host>/.well-known/apple-app-site-association` with no
   redirect and `application/json` content type, then verify Apple CDN retrieval.
5. Inject the exact same origin into `TeamWorkspaceInvitationRouter`; do not infer
   it from the incoming URL or an identity token.
6. Record staging and physical universal-link evidence in the final acceptance
   receipt before upload.

The app target resolves its entitlement path from the empty
`PINBOOK_TEAM_CODE_SIGN_ENTITLEMENTS` build setting. Only the opt-in xcconfig sets
that path, so current Release/TestFlight signing and production behavior remain
unchanged unless the release invocation deliberately selects it.
