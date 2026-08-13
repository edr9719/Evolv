# Evolv validation pilot operations

The first part of this invite-only pilot checks whether five fully repositioned captures made in one 20–30 minute session produce stable results. After a participant shares that test, they may separately choose whether future normal progress scans can contribute longitudinal evidence. Neither path validates tissue composition.

## One-time setup

Use the fail-closed readiness command for this phase. It verifies that the
bundle identifier, build number, analysis version, privacy boundaries,
migrations, Edge Functions, local database, and test plans agree:

```sh
scripts/evolv-pilot-readiness config
scripts/evolv-pilot-readiness local
```

Before producing an invite-only study build, run the consolidated Phase 5 pilot gate as well:

```sh
scripts/evolv-phase5-gate pilot --device PHYSICAL_IPHONE_DEVICE_ID
```

This permits a provisional `engineering-v1` pilot only; it does not validate thresholds or approve public analytical claims.

The deployment command intentionally refuses to continue while the Supabase
project is paused, when any required secret is missing or shorter than 32
characters, or unless the exact project reference is supplied as an explicit
confirmation. Secret values are passed through a permission-restricted
temporary environment file and are never printed:

```sh
export PILOT_INVITE_PEPPER='...at least 32 characters...'
export PILOT_ADMIN_SECRET='...at least 32 characters...'
export PILOT_CRON_SECRET='...at least 32 characters...'
export EVOLV_PILOT_DEPLOY_CONFIRM='zaqbnznrfvapbgrjxskv'
scripts/evolv-pilot-readiness deploy
```

For the first deployment, generate all three values without printing them:

```sh
scripts/evolv-pilot secrets
```

This creates `private/pilot/backend.env` with mode `600`. It is Git-ignored and
the deploy command loads only the three expected names without executing the
file as a shell script. Back it up in the same password manager or encrypted
offline location as the pilot photo private key. Existing files are never
overwritten.

Deployment is not a release gate by itself. Create a disposable invite after
deployment and run both the hosted penetration checks and the physical-iPhone
Vision plan:

```sh
export SUPABASE_PUBLISHABLE_KEY='...the key bundled by this release...'
export EVOLV_PILOT_TEST_INVITE='...one-use test invite...'
scripts/evolv-pilot-readiness live
scripts/evolv-pilot-readiness device --device PHYSICAL_IPHONE_DEVICE_ID
```

`scripts/evolv-pilot-readiness all --device ...` runs every non-deployment
gate. It never deploys, uploads a TestFlight build, creates a study, or creates
invites. The live test deliberately consumes its invite and deletes the test
participant at the end.

The tracked app contains only the P-256 public key. The private key was generated at `private/pilot/evolv-pilot-private.pem`, is ignored by Git, and must be backed up in a secure offline location. Losing it makes shared photo ciphertext permanently unreadable.

Restore and link the Evolv Supabase project, then apply and lint the schema:

```sh
supabase link --project-ref zaqbnznrfvapbgrjxskv
supabase db push --linked
supabase db lint --linked --schema public --level error --fail-on error
```

Generate three independent secrets of at least 32 random bytes and set them without committing or printing them:

```sh
supabase secrets set --project-ref zaqbnznrfvapbgrjxskv \
  PILOT_INVITE_PEPPER=... PILOT_ADMIN_SECRET=... PILOT_CRON_SECRET=...
supabase functions deploy pilot-api pilot-admin pilot-retention \
  --project-ref zaqbnznrfvapbgrjxskv --use-api
```

Store `PILOT_ADMIN_SECRET` in the researcher's local password manager and expose it only as `EVOLV_PILOT_ADMIN_SECRET` when running the CLI. Add `PILOT_CRON_SECRET` to GitHub Actions as the repository secret `EVOLV_PILOT_CRON_SECRET`; `.github/workflows/pilot-retention.yml` invokes the protected retention endpoint daily. Run it manually once and confirm success before inviting testers.

## Create the pilot and five invites

```sh
export EVOLV_PILOT_ADMIN_SECRET='...'
scripts/evolv-pilot create-study --name 'Evolv five-person validation pilot' --days 90 --capacity 5
scripts/evolv-pilot invites STUDY_ID --count 5
```

The invite tool writes one-use codes to `private/pilot/invites-STUDY_ID.txt` with owner-only permissions. Send one code to each tester. Never commit or paste this file into an issue.

## What testers do

1. Install the invited TestFlight build and open Settings → Help test Evolv.
2. Tap **Review sharing choices**, enter the one-use code, choose **Results only** (default) or **Results and selected photos**, confirm age 18+, and join.
3. Read the on-screen protocol. Use one camera/lens for all five sets.
4. Capture Set 1, then fully move away and reposition both the body and phone before Sets 2–5. Do not eat, drink, train, change clothing, room, lighting, phone height, or marked positions.
5. After each set, truthfully answer whether conditions stayed the same. Record any deviation rather than trying to hide it.
6. After Set 5, review the result. If sharing photos, tap each approved photo individually and confirm the selection. Otherwise use **Results only**.
7. Keep the displayed deletion code. Settings → Privacy & Data → Pilot data sharing can withdraw without deleting the local timeline.

## Optional contribution after the five-set test

Completing the first submission does not enroll a tester in ongoing sharing. A separate **Future progress scans** card appears only after that submission completes. The tester can choose:

- **Share future results:** after each future canonical progress scan finishes on-device analysis, Evolv shares only the structured allowlisted result. Photos remain on the iPhone.
- **Ask after each scan:** nothing is automatic. The scan-detail screen lets the tester share results only or select and approve individual required-pose photos for that one scan.

The choice applies only to scans captured after it was accepted. It excludes earlier timeline entries, five-set validation captures, and same-day extra scans. Turning it off takes effect locally immediately; queued remote cancellations retry when connectivity returns. Data already completed on the server is unchanged unless the tester uses **Delete my shared pilot data**.

This remains an explicit invite cohort bounded by the study capacity. Do not silently select “most active” production users. Create another reviewed cohort and consent version if the program later expands.

An offline or interrupted upload remains an encrypted retry package on the iPhone. Reopen Evolv or tap retry after connectivity returns. Repeated completion requests are idempotent and return the same receipt.

## Security and release gates

Run the static gates on every change:

```sh
scripts/test-evolv-pilot-security
scripts/test-evolv-analysis unit
```

The public `POST /pilot-api/health` response is also checked locally and after
deployment. It performs database reads against both pilot schema generations
and returns only service/schema/analysis/consent versions—never study or user
data. A deployed function with missing migrations therefore cannot report
healthy.

After creating a disposable invite, consume it with the live penetration suite:

```sh
export SUPABASE_PUBLISHABLE_KEY='...'
export EVOLV_PILOT_TEST_INVITE='DISPOSABLE-ONE-USE-CODE'
scripts/test-evolv-pilot-security
```

The live suite verifies anonymous denial, invite reuse, forged participant access, forged consent, consent/file mismatch, idempotent initialization and completion, and deletion-code invalidation. Also manually verify a selected-photo submission, an offline interruption after one object, retry, withdrawal, and token loss on a physical iPhone.

It also verifies that progress contributions require the separate `pilot-ongoing-v1` consent and are reported separately from consistency tests.

Do not distribute externally until all of these are true:

- RLS and private-bucket static gates pass.
- Results-only sends zero objects and no wrapped key.
- A photo cannot initialize without explicit selected-photo consent.
- The backend stores ciphertext that cannot be opened without the ignored researcher private key.
- One internal results-only submission and one selected-photo submission download correctly, then delete completely.
- The hosted privacy policy and App Store privacy answers match `growth/app-store/`.
- The physical-device Vision plan passes on the release iPhone.

## Researcher status, download, and report

```sh
scripts/evolv-pilot status STUDY_ID
scripts/evolv-pilot download STUDY_ID
scripts/evolv-pilot report private/pilot/downloads/TIMESTAMP/pilot-results.json
```

The default download contains structured results only. It never downloads photos. To deliberately download consented encrypted photos, verify the private key is available and use the exact opt-in flag:

```sh
scripts/evolv-pilot download STUDY_ID --include-photos
scripts/evolv-pilot stage private/pilot/downloads/TIMESTAMP
scripts/test-evolv-analysis device --device PHYSICAL_IPHONE_UDID
```

The tool verifies every ciphertext SHA-256, decrypts locally, and stages photos under the Git-ignored `ios/EvolvTests/Fixtures/Private/` directory. The local report separates `consistency_test` and `progress_scan`, then summarizes completion/upload failures, unexpected changes, abstentions, pose/region coverage, recorded deviations, device/camera/OS groupings, and processing timings. It contains no photos. Staged progress photos are labeled `longitudinal_observation_unlabeled`; they must not be treated as known body change without independent corroboration.

Interpretation:

- `consistent`: all four Set-1 comparisons had required core evidence and no change, conflict, processing failure, or recorded deviation.
- `limitedEvidence`: no change was claimed, but some required evidence was unavailable.
- `needsReview`: at least one unexpected change, conflict, processing failure, or real capture-condition deviation occurred.

Never treat unavailable evidence as a stable result. Review annotated physical-device artifacts before changing thresholds.

## Delete, close, and verify retention

```sh
scripts/evolv-pilot delete PARTICIPANT_ID
scripts/evolv-pilot close STUDY_ID
scripts/evolv-pilot retention
scripts/evolv-pilot status STUDY_ID
```

Closing immediately deletes study photo objects while retaining structured results until their 12-month deletion dates. Participant withdrawal or researcher deletion removes both immediately. The status and deletion-audit counts must match the expected submission/object counts after every cleanup operation.

## Troubleshooting

- **Project paused:** restore the Evolv project in Supabase, wait until its status is `ACTIVE_HEALTHY`, then link again.
- **Invite rejected:** codes are one-use, expire at pilot close, and are rate-limited. Create a new code instead of reusing one.
- **Upload queued:** keep the app installed, reconnect, unlock the iPhone, and reopen Evolv. The queue contains ciphertext only.
- **Token missing:** use the deletion code in Privacy & Data. A token cannot be reconstructed from Supabase because only its keyed hash is stored.
- **Photo decrypt fails:** stop. Confirm the ignored private key backup and public-key version; never replace the production public key mid-pilot.
- **Private fixture guard fails:** remove the file from Git tracking without deleting the local consented fixture, then rerun the guard.
