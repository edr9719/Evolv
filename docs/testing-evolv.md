# Testing Evolv analysis

For the invited five-person sharing backend, consent, encrypted photo handling, and researcher reports, also follow [pilot-validation.md](pilot-validation.md).

Evolv analysis version 5 is intentionally abstention-first. It retains the version-4 person-aligned extraction and adds known camera-configuration comparability. A passing test run proves that the software obeys its evidence rules; it does not by itself validate the provisional `engineering-v1` thresholds on people. Those thresholds remain limited until the held-out protocol below passes.

## One-command runner

Run commands from the repository root:

```sh
scripts/test-evolv-analysis unit
scripts/test-evolv-analysis device --device YOUR_IPHONE_UDID
scripts/test-evolv-analysis cloud-contract
scripts/test-evolv-analysis all --device YOUR_IPHONE_UDID
```

Find the physical iPhone UDID with:

```sh
xcrun xctrace list devices
```

The device command requires an explicit physical destination and exits instead of substituting a simulator. Before running it:

1. Connect and trust the iPhone.
2. Unlock it and keep it awake.
3. Enable Developer Mode under Privacy & Security.
4. Keep at least 1 GB free.
5. Confirm the phone appears under `== Devices ==`, not `== Devices Offline ==`.

The preflight verifies connection, lock state, Developer Mode, storage, and that the UDID is not a simulator.

If this Xcode version does not expose Developer Mode or free capacity in `devicectl` JSON, verify those two conditions manually and acknowledge only the unavailable checks:

```sh
EVOLV_DEVELOPER_MODE_CONFIRMED=1 \
EVOLV_DEVICE_STORAGE_CONFIRMED=1 \
scripts/test-evolv-analysis device --device YOUR_IPHONE_UDID
```

## What each mode proves

`unit` runs `Evolv-Unit.xctestplan` on a simulator with networking disabled. It covers:

- person-aligned translation, scale, and ±2° rotation invariance using exact masks and landmarks;
- torso and arm thickness recovery;
- the 0.85 same-pose comparability gate;
- front/side/back fusion and disagreement abstention;
- stable zero values versus missing evidence;
- literal physical direction and separate goal alignment;
- optional-pose isolation and removal of thigh visual claims;
- v3 decoding and v4 migration fields;
- orientation, storage, privacy, and safe wording;
- local five-set protocol eligibility, expiry, draft recovery, progress isolation, and result classification;
- the TestFlight-only gate, local-preview boundary, pilot consent rules, encryption envelope, and authenticated cancellation request;
- rejection of unsafe cloud prose.

`device` runs `Evolv-Vision-Device.xctestplan` on the selected iPhone. It runs the full Vision pose and segmentation path with generated front, side, and back fixtures, four identical simulated weeks, and a complete five-set local consistency-test evaluation. It also covers recompression, orientation, brightness, contrast, translation, ±2° rotation, valid crop, and ±3/5/8% scale transforms. Valid transforms must remain supported and stable. Deliberately invalid crop, occlusion, orientation/pose, and exposure fixtures must become unavailable.

`cloud-contract` first runs the mocked privacy and wording contract. It does not contact a service unless `EVOLV_CLOUD_CONTRACT_URL` is set. To exercise a deployed endpoint with `curl`:

```sh
EVOLV_CLOUD_CONTRACT_URL='https://YOUR_PROJECT.supabase.co/functions/v1/generate-insight' \
EVOLV_CLOUD_CONTRACT_KEY='YOUR_PUBLISHABLE_KEY' \
scripts/test-evolv-analysis cloud-contract
```

The request is [cloud-contract-request.json](../scripts/fixtures/cloud-contract-request.json). It contains derived structured signals only—no image, filename, landmarks, raw measurement, or identity. The runner rejects missing response fields and prohibited tissue claims.

## Fixtures and privacy

The nine public generated images are stored as app assets and described by [manifest.json](../ios/EvolvTests/Fixtures/Public/manifest.json). Images 1–3 are the mandatory analytical fixtures. Images 4–9 verify that showcase photos cannot affect analysis.

Consented real-person fixtures belong under:

```text
ios/EvolvTests/Fixtures/Private/
```

Use the manifest fields listed in that directory's README. The runner:

- fails if a private fixture is Git-tracked;
- stages private files into a temporary test-only resource directory;
- never adds them to the Evolv app target;
- removes the staging directory and regenerates the project after the run.

Before sharing a branch, verify manually:

```sh
git ls-files 'ios/EvolvTests/Fixtures/Private/*' 'ios/EvolvTests/Fixtures/StagedPrivate/*'
```

Only `Private/README.md` and `StagedPrivate/.keep` may appear.

## Reports

Each runner invocation creates:

```text
ios/build/analysis-validation/YYYYMMDDTHHMMSSZ/
```

The directory contains the raw `.xcresult`, Xcode log, `summary.json`, `tests.json`, `results.csv`, and exported attachments. Device attachments include:

- person masks;
- landmarks;
- torso and arm sampling lines;
- pose contributions and regional comparisons;
- safe wording output;
- timing, memory, and storage metrics.

Interpret the statuses literally:

- `stable`: supported comparison, delta clamped to zero inside the region band;
- `increase` / `decrease`: literal visual-feature direction, experimental while `engineering-v1` is active;
- `unavailable`: missing, incomparable, or conflicting evidence; never read this as stable;
- `pose_not_comparable`: the same-pose score fell below 0.85;
- `cross_pose_conflict`: supported pose deltas disagreed in direction or exceeded the spread limit.

Performance baselines are stored per device and OS by the test host. A later median three-pose run fails after a regression greater than 20% on the same configuration.

## Manual physical capture protocol

### Built-in five-set consistency test

In a Debug or TestFlight build, open Profile/Settings → **Help test Evolv**. This entry is intentionally absent from a public App Store build.

1. Allow 20–30 minutes and finish all five sets in one session.
2. Choose Front or Rear before Set 1. Evolv locks that camera for the full test; do not change devices or lenses.
3. Wear the same fitted or minimal clothing and keep the same room and lighting.
4. Keep the iPhone upright at about waist height. Mark both the phone and foot positions.
5. Do not eat, drink, exercise, or change clothing until all five sets are complete.
6. Capture only front, side, and back relaxed. Library selection and showcase poses are intentionally disabled.
7. After each set, fully step away and reposition both the phone and your body. Then answer whether the conditions stayed the same. Record any lighting, phone-position, clothing, or interruption change honestly.
8. Sets 2–5 show Set 1 as the on-device ghost overlay. Align to your own reference without forcing your body into the generic guide.
9. Complete the test within 60 minutes and on the same calendar day. If it expires, Evolv keeps the photos but marks the session protocol-ineligible.
10. Read the result literally: **Consistent** means no unexpected same-session visual change was found; **Limited Evidence** means the software could not support every core region; **Needs Review** means a change, conflict, processing failure, or reported condition change occurred. Consistency does not prove measurement accuracy.

An eligible camera-only progress scan from the last 30 minutes may be reused as Set 1, leaving at least 30 minutes to finish. Otherwise the first newly captured set becomes today's canonical progress scan only when no canonical scan exists that day; when one already exists it becomes a validation anchor. Sets 2–5 are always grouped as consistency repeats in Timeline and must not affect progress, baseline, reminders, or streaks. The consistency test itself remains local. An invited adult may separately review and approve a pilot submission after Set 5; results-only is the default, and no photo is included without individual selection and final confirmation.

Run this flow once with the front camera and once with the rear camera before release. Force-quit partway through one set to verify draft recovery, and leave one session longer than 60 minutes to verify that its completed records are preserved rather than silently deleted.

### General repeat capture protocol

For every repeat scan:

1. Use the same room, background, phone, lens, phone height, and portrait orientation.
2. Mark the phone/tripod and foot positions on the floor.
3. Use diffuse front lighting; avoid a strong side or rear shadow.
4. Keep head through upper thighs visible for front, side, and back relaxed.
5. Keep the torso complete and relaxed arms separated from the torso.
6. Match the baseline ghost overlay without trying to match the example person's proportions.
7. Remove loose outerwear; record clothing, hydration, time, workout state, device, and environment.
8. Fully leave the marked position between repeat captures, then reposition. Consecutive shots without repositioning are not repeatability evidence.

Run at least five repositioned scans per pilot participant. Review the image, mask, landmarks, and sampling-line attachments whenever a supported result is surprising.

## Real-person calibration and held-out validation

Use [participant-manifest-template.csv](validation/participant-manifest-template.csv) before collecting scans. Assign participants—not scan pairs—to `calibration` or `heldout` before thresholds are derived. The same participant must never appear in both groups.

Minimum phases:

- engineering pilot: at least 5 people × 5 fully repositioned scans;
- pre-release: at least 30 diverse participants × 5 scans, split by participant;
- longitudinal: 8–12 weeks under standardized capture conditions.

Record regional repeatability rows with [repeatability-results-template.csv](validation/repeatability-results-template.csv), then run:

```sh
scripts/evolv-validation-stats \
  docs/validation/repeatability-results.csv \
  ios/build/analysis-validation/repeatability-report.json
```

The report derives calibration candidates from the calibration participants and evaluates only held-out participants for promotion. It reports:

- participant-clustered false-change rate and one-sided 95% upper bound;
- unexpected abstention separately;
- error and abstention by evidence strength;
- body type, skin tone, clothing, device, and environment subgroups;
- Bland–Altman limits for repeated Evolv features in the same normalized units.

The script intentionally has no tape-measure comparison field. Tape circumference is not interchangeable with silhouette width. For the longitudinal protocol, use [longitudinal-template.csv](validation/longitudinal-template.csv), measure tape values in triplicate with a blinded measurer, and evaluate direction only after change exceeds that method's repeatability error. Prefer an independent 3D scan or manually annotated contour for geometric accuracy.

The default unexpected-abstention cap is a provisional 15%; change it only in a preregistered validation protocol:

```sh
EVOLV_MAX_ABSTENTION_RATE=0.10 scripts/evolv-validation-stats INPUT.csv OUTPUT.json
```

## Release gates

Do not promote `engineering-v1` to `validated-v1`, produce a TestFlight build, or strengthen visual-shape wording unless all applicable gates pass:

- unit suite passes;
- exact and every valid transformed public fixture produce zero false-change claims and no unexpected abstention;
- every deliberately invalid fixture abstains;
- optional images 4–9 cannot alter any analytical output;
- no fixture photo appears in a network payload;
- physical-device median performance has not regressed more than 20%;
- calibration and held-out participants are disjoint;
- held-out participant-clustered false meaningful-change one-sided 95% upper bound is at most 5%;
- unexpected abstention is below the preregistered cap;
- higher evidence strength has lower error and abstention than lower evidence strength;
- subgroup results have been reviewed for material disparity.

Until those human-validation gates pass, the app may show stable/raw visual comparisons, but non-neutral changes remain experimental/limited and wording stays at “silhouette increased/decreased/stable.”

## Troubleshooting

- `Missing weights path ... human_pose` on a simulator: expected reason the Vision plan is device-only; run `unit` for simulator-safe checks.
- iPhone appears offline: reconnect, unlock, trust the Mac, open Xcode's Devices and Simulators window, and wait for preparation to finish.
- device locked during tests: keep Auto-Lock disabled temporarily and rerun.
- manifest missing: regenerate the project with `cd ios && xcodegen generate --spec project.yml`.
- valid fixture unavailable: inspect its mask/landmark/sampling attachment before adjusting any threshold. Fix extraction or fixture validity first; do not turn an unavailable result into stable.
