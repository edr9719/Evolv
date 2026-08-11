# Evolv pilot data inventory — version 2

Effective implementation date: August 10, 2026. Initial-test consent: `pilot-consent-v1`. Ongoing-contribution consent: `pilot-ongoing-v1`. Payload schema: `1`.

This inventory is the allowlist for the invited consistency pilot. Adding a transmitted field requires a new inventory and consent review.

| Field group | Examples | Purpose | Retention | App Store category |
|---|---|---|---|---|
| Opaque access | participant UUID, hashed participant token, hashed deletion code, one-use invite hash | Enroll, authenticate, delete, prevent replay | Until withdrawal, or until the pilot is closed and that participant's last result expires | Identifiers → User ID |
| Consent | consent version, adult confirmation, contribution type, share scope, selected-photo count, acceptance time | Prove the participant's exact choice; distinguish the five-set test from separately approved future scans | 12 months after submission or immediate withdrawal | Other Data / App Functionality |
| Regional results | normalized baseline/current feature, literal delta, stable/increase/decrease/unavailable, evidence reason | Evaluate repeatability and false changes | 12 months after submission or immediate withdrawal | Health & Fitness → Fitness |
| Pose evidence | pose-match score, supported/unavailable contribution, conflict/failure reason codes | Diagnose analysis consistency without raw landmarks | 12 months after submission or immediate withdrawal | Health & Fitness → Fitness; Diagnostics |
| Test protocol | set number/time, same-conditions answer, deviation reason codes | Separate algorithm errors from changed capture conditions | 12 months after submission or immediate withdrawal | Health & Fitness → Fitness |
| Future progress context | contribution type, local scan UUID, scan/analyzed times, comparison availability | Group separately consented canonical progress observations without uploading the personal timeline | 12 months after submission or immediate withdrawal | Health & Fitness → Fitness |
| Runtime context | app build, analysis/threshold version, iPhone hardware model, iOS version, camera position and lens type | Reproduce configuration-specific failures | 12 months after submission or immediate withdrawal | Diagnostics → Performance Data |
| Individually selected photos | normalized metadata-free JPEG encrypted as AES-256-GCM ciphertext; set and pose labels; ciphertext size and SHA-256 | Inspect pose, framing, segmentation, landmark behavior, and build consented private fixtures | Pilot close date, at most 90 days after activation, or immediate withdrawal | User Content → Photos or Videos |
| Submission operations | idempotency UUID, object UUID, receipt code, completion timestamps | Recover partial uploads and prevent duplicates | 12 months after submission or immediate withdrawal | Other Data / App Functionality |
| Deletion audit | keyed pseudonymous reference, reason, object/submission counts, deletion time | Verify deletion operations without retaining participant data | Operational audit retention; no source photos/results | Diagnostics |

Explicitly excluded from pilot transmission: names, email addresses, phone numbers, location, advertising identifiers, unique device identifiers, filenames, raw Vision landmarks, person masks, body descriptions, raw height, raw weight, tape measurements, photo-library metadata, and unselected photos.

The unauthenticated pilot health endpoint returns only static service, schema,
analysis, and accepted-consent version identifiers. It reads no participant or
study rows and returns no user data.

Ongoing contribution is not retroactive. Same-day extras and validation-session scans are ineligible. Structured results may be automatic only after the participant chooses **Share future results**. Every future photo requires a fresh scan-level choice, individual selection, and final approval. Turning ongoing contribution off stops future authorization immediately; completed submissions follow the deletion and retention controls above.

Cloud-written insights are a separate opt-in system. Their derived request is not added to or enabled by pilot enrollment.
