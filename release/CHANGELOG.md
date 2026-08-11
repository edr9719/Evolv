# Changelog

All notable changes to Evolv are documented here.

The format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project aims to adhere to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

- Added a fail-closed pilot rollout gate covering configuration consistency, local migrations, Edge Function health, hosted penetration testing, and explicit physical-iPhone validation.
- Added a privacy-safe pilot health contract that verifies both database schema generations without exposing study or participant data.
- Fixed missing explicit `service_role` table and identity-sequence privileges that would have prevented the private pilot Edge Functions from operating in production.
- Fixed physical-device preflight to accept either the CoreDevice identifier or hardware UDID while still rejecting disconnected and simulated devices.
- Added separate, future-only consent for ongoing canonical progress evidence after a completed five-set pilot submission.
- Added results-only automatic contribution with no photo bytes, an ask-every-scan mode, and fresh individual approval for every contributed photo.
- Added server-enforced cohort capacity, ongoing-consent versioning, consistency-first eligibility, separate progress exports/reports, and offline-safe cancellation.
- Added invite-only validation sharing with results-only as the default and individual photo approval after a completed five-set test.
- Added on-device photo normalization and encryption, ciphertext-only retry storage, idempotent uploads, withdrawal, and recovery-code deletion.
- Added a private Supabase pilot backend with one-use invites, forced RLS, private ciphertext storage, retention enforcement, and researcher-only export tooling.
- Added local pilot reports, consented private-fixture staging, privacy disclosures, App Review guidance, and automated security gates.
- Restored persistent, safe-area camera controls with an explicit Front/Rear switch and front-camera default for solo capture.
- Added correctly mirrored live previews and local ghost overlays while keeping saved analysis pixels upright and unmirrored.
- Added analysis v5 camera-configuration comparability and backward-compatible capture metadata.
- Replaced the legacy app icon set with the new opaque Evolv icon.
- Added analysis v4 with person-aligned extraction, same-pose comparability, cross-pose fusion, literal physical direction, and separate goal alignment.
- Added provisional region-specific engineering stability bands derived from deterministic public-fixture transformations; non-neutral results remain experimental until held-out validation.
- Added physical-iPhone fixture validation for orientation, recompression, lighting, translation, rotation, crop, scale, invalid inputs, privacy, and performance regression.
- Changed analytical wording to observable silhouette evidence and preserved unavailable regions instead of inventing confidence or progress.
- Added realistic pose examples, landmark-based camera alignment, local previous-photo overlays, and pose-specific review checklists.
- Added a review-first photo flow with truthful automatic-check states.
- Added targeted pose replacement without losing accepted photos.
- Added one-progress-scan-per-day guidance and separate same-day extras.
- Added complete scan details with every required and showcase photo.
- Added local storage protection, metadata stripping, and opt-in cloud wording.
- Kept unsupported body regions unavailable instead of guessing progress.
