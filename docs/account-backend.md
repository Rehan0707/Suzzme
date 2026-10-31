# Suzzme accounts

Suzzme keeps conversations, memory, knowledge-source content, and raw source
records on the device. The account backend stores a Firebase user ID, email
address, optional display name, and creation/last-seen times. With explicit
Mac-side iPhone sharing, it also stores one bounded, prepared Daily Summary per
account. The schema is in `supabase/migrations/20261023193000_app_accounts.sql`
`supabase/migrations/20261025190000_companion_summaries.sql`, and
`supabase/migrations/20261029000000_account_deletion.sql`. The companion
table and its four UID-scoped RLS policies were applied to the production
Supabase project through the SQL Editor on 26 October 2026.

On 29 October 2026, the production SQL Editor applied the account deletion
grant and Firebase-UID-scoped DELETE policy. A follow-up `pg_policies` query
confirmed exactly one account DELETE policy with issuer, audience, and UID
checks. Deleting `app_accounts` cascades its prepared companion summary.

Google sign-in uses Firebase Authentication project `suzzme-e70f2`. Google
source permissions, such as Gmail, are separate and are not requested during
account sign-in. The Apple app registered in Firebase has bundle ID
`rehan.Suzzme`.

The Supabase project is `xkddrfkdesagugtxuwzu` in the Suzzme organization.
Its Third-Party Auth integration trusts only Firebase project `suzzme-e70f2`.
The app uses a publishable API key, never a secret or service-role key. Firebase
ID tokens lack a database `role` claim by default, so the account table allows
the `anon` Postgres role only when a *verified* Firebase token has this
project's issuer and audience. Row-level policies also bind the Firebase UID
and email to that token. Requests without a matching token cannot read or
write account records. A project administrator can count users with:

```sql
select count(*) from public.app_accounts;
```

On successful Google sign-in the app obtains a Firebase ID token and upserts
the signed-in user's account record through Supabase's Data API. The unique
Firebase UID prevents duplicate user rows on repeated sign-ins. If saving the
record fails, the sign-in page displays an error rather than claiming that the
account was set up.

Mac sharing is off by default and scoped to the signed-in Firebase UID. Enabling
it prepares a fresh summary, then publishes only its display-ready narration,
up to 12 short day items, source labels, limitations, and timestamps. It does
not publish raw records, source references, credentials, memory, or action
capabilities. The iPhone reads the row through the same verified Firebase token
and UID-bound row-level policy, and caches the last valid response under a
UID-specific, protected local file. Turning sharing off, clearing proactive
data, and source revocation attempt to delete the remote row. If deletion
cannot reach the backend, Mac settings display an error and record a pending
removal for retry on the next authenticated Mac refresh; re-enabling sharing
waits for that removal to succeed. The row is otherwise replaced by each new
publish and retained until removed or the account is deleted. The iPhone labels
its last cached copy with its actual sharing time.

## Live verification (23 October 2026)

- The Supabase project has the Firebase third-party authentication integration
  enabled for `suzzme-e70f2`.
- The applied `app_accounts` table has RLS enabled and three policies. An
  administrator query returned zero account rows.
- The public Data API returned `[]` with an exact count of zero for a request
  without a Firebase ID token.
- A direct unauthenticated insert returned HTTP 401 with PostgREST error
  `42501` (`new row violates row-level security policy`). A second read still
  returned zero rows, so the probe did not leave test data.

The remaining end-to-end acceptance check is a real Google sign-in in the
installed app, followed by an administrator check that exactly one account row
appears and that repeating sign-in updates that row. This requires a user to
complete the Google consent flow on a device. Do not use a fabricated token or
test account in production to substitute for that check.

## Companion summary deployment (26 October 2026)

The production SQL Editor reported success for the companion-summary schema.
The Table Editor shows `public.companion_summaries` with `firebase_uid`, `payload`,
and `published_at`. The policy view shows RLS enabled and separate read, insert,
update, and delete policies bound to the verified Firebase UID. A real Mac-to-iPhone
publish and receive still requires signing in to the same account on both devices,
enabling sharing on Mac, and preparing a Daily Summary.
The SQL was applied through the dashboard rather than Supabase CLI migration
tracking; the checked-in migration is replay-safe for later ledger synchronization.

## Account and companion checks (29 October 2026)

Launch routing now waits for Firebase's account restoration callback. A previous
guest choice no longer skips authentication on the next launch; a valid restored
account still opens its own setup or app. Account changes clear the previous
summary presentation and retire pending loads. On iPhone, a successful sign-in
starts fetching the prepared Mac summary during setup, and the foreground app
checks again every 30 seconds. Guest Today also has a direct sign-in link.

Transport requests retain one Firebase UID and token, bypass stale HTTP caches,
and use a 20-second timeout. Returned rows must match the requested UID before
being cached. Mac publication ensures the account row exists first. Uploads and
removals are ordered so an earlier upload cannot restore a summary after sharing
is disabled. Sharing remains explicitly enabled per account on the Mac.

`Suzzme/Validation/account-companion-check.sh` runs 20 isolated checks covering
launch routing, separate Mac/iPhone HTTP sessions, account isolation, removal,
outages, bounds, and upload/removal ordering. These use synthetic identities and
an in-process transport fixture, not production account tokens. Read-only live
checks returned HTTP 200 and zero anonymously visible rows for both
`app_accounts` and `companion_summaries`. This confirms basic endpoint access
and anonymous visibility for those requests; an authenticated same-account
publish/receive on the two devices is still a separate acceptance check.

### Companion execution and readouts

The iPhone runtime now opens neither the Mac's source-information stores nor
its memory/preparation stores. Its primary and fallback intelligence providers
refuse local extraction and generation. Today, Summary, and Settings receive
the bounded published payload; reading it uses speech playback rather than an
iPhone language model. Signed-out iPhone launches require account sign-in.

The Mac's existing scheduled worker owns routine preparation at the selected
time (08:00 by default). The Mac must be running and awake; a missed current-day
slot catches up after wake. Optional schedule and urgent-update metadata travel
inside the existing version-1 payload. Older payloads still decode and can be
read manually. Routine automatic readouts require a fresh summary prepared at
or after the chosen time and retain one receipt per account and scheduled day.
Urgent readouts ignore that routine time, expire after fifteen minutes, and use
bounded account-specific receipts to avoid replay.

When Mac Time-Sensitive Help and iPhone sharing are enabled, the Mac checks
already-authorized source updates once a minute while its session is active.
New source fingerprints trigger fresh evaluation; unchanged facts are evaluated
at most every five minutes. This is polling, not an instant provider webhook.
Foreground interaction, sleep, session lock, and cancellation take precedence.

Automatic iPhone readouts currently require the app to be active and spoken
responses enabled. Closed-app urgent delivery is not configured: an APNs
provider/device-registration pipeline and eligible signing capabilities remain
required. Background wakeups do not guarantee arbitrary full spoken playback.
The app does not simulate background delivery or keep silent audio running.

The updated account/transport/readout checks pass 31 cases. The existing
scheduled worker checks pass another 31 cases, including chosen-time, DST,
wake/catch-up, single-run, and cancellation behavior. Live Mac publication was
confirmed in the app after the owner enabled sharing on 29 October. Simulator
Google sign-in and authenticated receive remain separate from those results.

The final Mac publish path also reads the payload back through the authenticated
phone endpoint and compares it with the encoded publication before reporting
success. This live round trip succeeded at 19:38 local time on 29 October.
Mac and arm64 iOS simulator builds passed. Fifteen voice recovery checks passed,
including full-summary narration, bringing the focused checks to 77. Both
existing iOS 27 simulators timed out during boot after 60 seconds, and restarting
Device Hub did not make either device available. Google sign-in and the received
iPhone screen therefore remain unverified; no simulator credentials were entered.
Time-Sensitive Help remains off in the owner's Mac preferences pending their
choice to enable ongoing urgent monitoring.

### iPhone summary presence

A recently received Mac summary (generated within the last hour) can start the existing ActivityKit Live Activity while Suzzme is open. Compact and minimal Dynamic Island presentations show the original small mascot; the expanded presentation offers Read summary. Tapping opens `suzzme://summary` and selects the companion Summary tab. No summary text, account identifier, or source content enters the activity payload. The in-app top presence banner has been removed from the iPhone root.

Summary activities use the default persistent ActivityKit style, so an existing activity can remain visible when leaving the app; voice sessions retain their transient style and take foreground priority. Account clearing retires the summary presentation. User dismissal is respected. iPhones without Dynamic Island use the system Lock Screen presentation. Apple controls placement and visibility. This does not add APNs delivery: a new summary received while the app is terminated still requires the separate push pipeline.
