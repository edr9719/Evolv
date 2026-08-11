# App Store Connect Privacy Guidance

Reviewed against the iOS implementation on August 10, 2026. Recheck these answers whenever networking, analytics, accounts, subscriptions, or storage behavior changes.

## Data that stays on device

The following stays in Evolv's private app container during normal timeline use and is not transmitted unless the user separately approves an invited pilot submission:

- User photos selected or captured for scans
- Raw body measurements and weight
- Vision landmarks, silhouette profiles, and normalized pixel dimensions
- Scan notes, capture assessments, and local analysis files

Apple-controlled iCloud or computer device backup does not turn Evolv into the collector of that data. However, the invited pilot does collect the categories listed below, so the production privacy label must reflect the feature even though it is optional and invite-only.

## Invited validation-pilot collection

The pilot is ongoing declared collection, not an ad-hoc feedback exception. Participants first choose Results only by default or Results and individually selected photos for the five-set test. After that submission, a separate consent can apply only to future canonical progress scans: automatic structured results with no photos, or an ask-every-scan mode. Every ongoing photo is selected and approved for that individual scan. Conservatively declare:

- Health & Fitness → Fitness: linked to an opaque participant, not used for tracking, purpose Analytics and App Functionality.
- User Content → Photos or Videos: collected only when the participant individually selects photos, linked to an opaque participant, not used for tracking, purpose Analytics.
- Diagnostics → Performance Data: processing timings and non-sensitive failure reason codes, linked to an opaque participant, not used for tracking, purpose Analytics.
- Identifiers → User ID: opaque pilot participant ID, linked to the user, not used for tracking, purpose App Functionality and Analytics.
- Device ID: **No**. The app shares iPhone hardware model and OS version, not a unique device identifier.

The pilot payload excludes names, emails, location, advertising IDs, filenames, raw landmarks and masks, raw height and weight, and tape measurements. Selected photos are encrypted before upload. The private decryption key remains outside Supabase. Ongoing contribution is future-only and excludes same-day extras and validation scans.

## Optional cloud-written insight

The feature is off by default and requires an explicit toggle. When enabled, the app transmits a derived fitness-trend summary for App Functionality. It contains high-level direction/confidence/evidence categories, scan count and timing, selected fitness goal, measurement-agreement categories, and optional scan-condition codes. It contains no photo, filename, landmark, raw weight, raw tape measurement, account ID, advertising ID, or app-generated user ID.

Confirm the Supabase function and AI provider's retention configuration before submission. If the derived summary is retained beyond servicing the request, the conservative App Store Connect declaration is:

- Data type: Health & Fitness → Fitness
- Linked to the user: No
- Used for tracking: No
- Purpose: App Functionality

If server logs retain request metadata that Apple classifies separately, disclose it according to the actual production retention policy. Do not mark Photos or Videos as collected unless a future build begins transmitting them.

## Other answers for the current build

- Tracking: No
- Advertising: No
- Third-party advertising: No
- Third-party behavioral analytics SDK: No. User-approved pilot evidence is declared above for Analytics/App Functionality purposes.
- Account creation: No
- Precise or coarse location: No
- Contacts: No
- Photos or videos collected off device: Yes, only for individually approved invited-pilot photos
- Diagnostics collected off device: Yes, limited pilot processing timing/failure codes
- Purchases: the current purchase service is a local test implementation. Reassess when StoreKit production purchases ship.

## Submission checks

- Verify cloud insights still defaults to off after upgrade and clean install.
- Confirm network inspection shows no request while the toggle is off.
- Inspect the cloud payload and server logs for photos, filenames, landmarks, raw measurements, or identifiers.
- Verify results-only pilot submissions contain zero object uploads and no wrapped photo key.
- Verify photo uploads cannot initialize without results-and-selected-photos consent and at least one selected photo.
- Verify future results remain off until a completed consistency submission and separate `pilot-ongoing-v1` choice.
- Verify turning future contribution off immediately prevents new submissions and cancels incomplete ones after reconnection.
- Verify earlier timeline scans, same-day extras, and validation scans cannot enter ongoing contribution.
- Verify withdrawal and deletion-code flows delete server objects and structured results without deleting the local timeline.
- Verify the pilot close date and both retention dates shown in the app match the backend.
- Verify `docs/pilot-data-inventory.md` matches every transmitted field.
- Confirm the hosted privacy-policy page matches `privacy-policy.md`.
- Update the privacy label before enabling analytics, crash reporting, accounts, or real subscription processing.
