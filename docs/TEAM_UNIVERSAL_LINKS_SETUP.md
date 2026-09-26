# Team invitation Universal Links setup

Status: source-complete, production default-off.

The app now routes `NSUserActivityTypeBrowsingWeb` and HTTPS URLs through the
injected `TeamWorkspaceInvitationRouter`. Disabled production runtime accepts no
invitation. Enabled runtime accepts only the exact configured HTTPS origin and
canonical `/join?invite=<43-character-token>` grammar; alternate hosts, paths,
queries, fragments and encodings remain closed.

Infrastructure must complete these steps before an archive may enable the
capability:

1. Select `Config/TeamWorkspace.opt-in.xcconfig` only for the final archive.
2. Create ignored `Config/TeamWorkspace.xcconfig.local` with all nine approved
   public values:

   ```xcconfig
   PINBOOK_TEAM_SERVICE_ORIGIN = https:/$()/team.example.com
   PINBOOK_TEAM_APPLE_CLIENT_ID = <approved-apple-service-id>
   PINBOOK_TEAM_GOOGLE_NATIVE_CLIENT_ID = <approved-native-client-id>
   PINBOOK_TEAM_GOOGLE_REDIRECT_SCHEME = <approved-reversed-client-id>
   PINBOOK_TEAM_GOOGLE_SERVER_CLIENT_ID = <approved-server-client-id>
   PINBOOK_TEAM_AUTHORITY_EPOCH = <approved-positive-integer>
   PINBOOK_TEAM_TERMS_URL = https:/$()/example.com/terms
   PINBOOK_TEAM_PRIVACY_URL = https:/$()/example.com/privacy
   PINBOOK_TEAM_INVITATION_HOST = team.example.com
   ```

   The empty `$()` prevents xcconfig from treating the second slash in an
   HTTPS URL as a comment. These values are public configuration, never client
   secrets. The opt-in file maps the registered Google callback scheme to the
   exact approved redirect scheme.
3. Add Associated Domains to the registered App ID and regenerated provisioning
   profile. The opt-in xcconfig selects `Config/PinbookTeamUniversalLinks.entitlements`.
4. Generate the exact file with
   `scripts/generate-team-aasa.sh APPLE_TEAM_ID APP_BUNDLE_ID OUTPUT_PATH`, publish it as
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
