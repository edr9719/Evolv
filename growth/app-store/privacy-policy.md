# Evolv Privacy Policy

Effective date: August 10, 2026

Evolv is designed so your progress photos and measurements stay under your control. This policy explains what the app stores, what can leave your device, and the choices available to you. Your photos stay on your iPhone unless you explicitly choose specific photos to share with Evolv through an invited consistency pilot.

## Data stored on your device

Evolv stores the following in its private app container on your iPhone:

- Progress photos you take or select
- Measurements, goals, scan conditions, and preferences you enter
- On-device capture assessments and physique-analysis results

Scan photos are normalized and saved without source photo metadata such as location. Evolv applies iOS complete file protection to scan photos, analysis records, and app state so those files are unavailable while the device is locked. The app does not copy a library photo back into or modify the original item in Apple Photos.

Apple may include Evolv's app container in an iCloud or encrypted computer backup according to your device and backup settings. Those backups are controlled by Apple, not by Evolv. Deleting a scan from the active app does not necessarily remove an older copy from an existing Apple backup.

## On-device analysis

Capture checks and body-region analysis run on the device. Normal progress analysis does not upload progress photos, filenames, body landmarks, or raw measurements. Regions without supported comparison evidence are left unavailable rather than guessed.

## Optional invited consistency pilot

TestFlight users with a one-use invite may choose to share a completed five-set consistency test. The default choice is **Results only**. Shared results can include normalized regional features and deltas, pose-match and evidence status, conflicts and processing reason codes, test conditions and deviations, processing timing, app and analysis versions, iPhone model, iOS version, and camera configuration.

Results-only submissions do not include photos, filenames, raw body landmarks or masks, names, email addresses, location, advertising identifiers, raw height or weight, or tape measurements.

You may instead choose **Results and selected photos**. Evolv shows all eligible test photos and requires you to select the individual photos you approve. Photos you do not select remain only on your iPhone. Selected photos are normalized to remove source metadata, encrypted on your iPhone with a new submission key, and uploaded as ciphertext to private Supabase storage. The corresponding decryption private key is held separately by the Evolv researcher and is not stored in the app or Supabase. Supabase can store the encrypted bytes but cannot decrypt the photo content with the information stored there.

Pilot participation requires confirmation that you are 18 or older. Evolv uses an opaque participant identifier rather than an account, name, or email. Pilot sharing is separate from cloud-written insights; enabling or disabling either choice does not affect the other.

Each pilot has a fixed close date, shown in the app. Shared pilot photos are deleted no later than that close date. Structured pilot results are deleted 12 months after submission. You receive a deletion code and can withdraw at any time; withdrawal deletes shared pilot photos and results without deleting scans in your local timeline.

After a completed five-set submission, you may make a separate choice about future normal progress scans. **Share future results** sends the allowlisted structured analysis after each eligible on-device analysis and never includes photos. **Ask after each scan** sends nothing automatically; you decide for that scan whether to share results only or individually selected required-pose photos. This choice is not retroactive and does not include earlier scans, same-day extra scans, or consistency-test captures. Every future photo requires a fresh scan-level selection and approval.

You can turn future contribution off at any time. Turning it off stops new authorization on the iPhone immediately and cancels incomplete progress submissions; completed submissions remain subject to the deletion controls and retention periods above. Evolv does not silently enroll active users or select a “most active” group. Ongoing contribution remains limited to the invite-only pilot and its participant capacity.

## Optional cloud-written insights

Cloud-written insights are off by default. If you explicitly enable them in Privacy & Data, Evolv sends a derived trend summary to its insight service. The summary can include scan counts and timing, your selected fitness goal, high-level directional body-region signals, confidence and evidence status, measurement-agreement categories, and scan-condition reason codes.

The request does not include photos, filenames, body-landmark coordinates, raw tape measurements, or an Evolv user identifier. Supabase provides the network function and an AI model provider may process the derived summary to write the response. This processing is used only to provide the requested insight, not for advertising or cross-app tracking. You can turn cloud-written insights off at any time; on-device summaries remain available.

## Camera and photo-library access

Evolv requests camera access only to capture scan photos. It requests photo-library access only when you choose an existing photo. The app receives only the photo you select through Apple's picker; it does not browse or upload your library.

## Analytics, advertising, and accounts

Evolv does not use advertising trackers, does not sell personal data, and does not require a conventional account. Invited pilot participants receive an opaque access token stored in the iPhone Keychain. Evolv does not use a third-party behavioral analytics SDK. Pilot evidence is transmitted only under the choices described above.

## Subscriptions

When App Store subscriptions are enabled, Apple processes purchase and billing information. Evolv receives entitlement status, not your full payment-card details. Apple's privacy policy governs App Store transactions.

## Retention and deletion

Local data remains in the app until you delete an individual scan, delete all scan data, reset Evolv, or remove the app. Privacy & Data provides controls to delete scans and measurements. Deletion from Evolv is permanent for the active app installation; Apple backups may retain an earlier snapshot until you update or remove those backups.

Deleting a local scan does not by itself delete an already approved pilot submission, and deleting a pilot submission does not alter the local timeline. Privacy & Data includes a separate pilot deletion control. The deletion code can request deletion even after reinstalling the app.

## Children

Evolv is not directed to children under 13 and is not a medical service. It provides visual progress documentation, not a diagnosis or clinical body-composition measurement. The invited consistency pilot is limited to adults age 18 or older.

## Changes

If this policy changes materially, the effective date above will be updated and the revised policy will be made available with the app's publishing materials.

## Contact

For privacy or support questions, use the Evolv support page: https://apps.10x.app/build-a-modern-mobile-app-called-evolv-an-ai-p/support
