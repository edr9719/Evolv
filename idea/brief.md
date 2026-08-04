## Evolv — Final Build Plan

**Tagline:** See what the mirror misses.
**Core question the app answers:** *"Am I actually making progress?"*
**Tone:** Calm, premium, honest. Never hype, never fake science, never invented progress.

---

## Pre-Build Confirmation

### Product
AI-guided physique progress tracker. Users capture consistent front/side/back scans on a cadence and receive honest, sometimes-neutral, sometimes-negative AI analysis grounded in baseline measurements, updated measurements, weight trends, and visual scan consistency.

### v1 Feature Set (in scope)
1. **Onboarding** — welcome carousel (consistency education: same location, lighting, angle, distance), profile setup (goal, height, weight, experience), optional measurements (arms/chest/waist + optional shoulders/thighs), tracking cadence (daily/weekly/biweekly/monthly, weekly recommended), Baseline Physique Snapshot reveal.
2. **Guided Photo Capture** — silhouette overlay, live coaching strip (distance, framing, lighting, angle), front/side/back required + optional flex poses, post-capture consistency confidence score with honest warnings ("Lighting differs from previous scans — confidence reduced").
3. **Home Dashboard** — Progress Score 0–100 hero, momentum delta, Weekly AI Summary card, current streak, last scan, mini progress graph, prominent "Upload New Scan" CTA, estimated directional metrics (arms / chest / waist / visual muscularity).
4. **AI Analysis Screen** — region-highlighted body diagram, per-region status (Green improving / Yellow stable / Red stalled-declining), confidence chips, honest text insights, plateau detection.
5. **Transformation Timeline** — before/after drag-slider, week-to-week and month-to-month comparison, first-vs-latest cinematic view.
6. **Stats Screen** — weight history, measurement trends, scan frequency, consistency streaks, estimated progress rate, training consistency, minimal charts.
7. **Premium Paywall** — Free (limited scans + basic timeline) vs Premium (unlimited scans, full AI analysis, advanced comparisons, score, plateau detection, long-term tracking). Pricing displayed: $9.99/mo, $69.99/yr. UI only in v1.
8. **Scan Library** — chronological scan history with thumbnails and consistency badges.

### Explicit exclusions (v1)
- No real cloud vision model — deterministic mock AI engine derives believable, sometimes-negative outputs from scan metadata, measurement deltas, and weight trends.
- No real subscription billing — paywall UI ships; StoreKit/Superwall deferred.
- No cloud sync, accounts, or multi-device — local SwiftData only.
- No social, sharing, friends, or leaderboards.
- No workout/nutrition logging beyond bodyweight and optional simple measurements.
- No medical claims, body-fat % estimates, or muscle-mass numbers — directional language only.

### Data stance
Mock-first, fully local. SwiftData models: `UserProfile`, `Measurement`, `Scan` (with image refs + consistency scores), `AnalysisInsight`, `ProgressScore`. Mock AI is a deterministic rules engine so output feels honest across sessions.

### Onboarding flow
`welcome-carousel` (with strong consistency education) → personalization quiz (goal/height/weight/experience) → optional measurements step (interactive body diagram + sliders) → cadence selection → **Baseline Physique Snapshot reveal**. Paywall is *not* first — it surfaces when the user hits a free-tier limit, protecting the trust promise.

### Design System (final)

**Reference direction — Custom blend**
- **Primary:** Apple Health — restrained anatomy/region visuals, clean minimal charts, calm hierarchy.
- **Secondary:** Levels — dark-premium translucency, soft gradients, credible biometric tone.
- **Light influence:** Cal AI — emotional body-scan moment and paywall reveal pattern.
- **Avoid:** Whoop's high-contrast performance-data density and gym-bro intensity.

**Mapped style seed:** `clinical` (health-grade trust) with `glassy` surface treatment.

**Selected palette — Obsidian Mint**
- Background `#0B0F0E` — deep obsidian dark-mode shell
- Surface `#141A19` — translucent graphite cards with subtle glass blur
- Primary / Text `#F2F5F3` — soft off-white, never pure white
- Accent `#7BE3B3` — restrained mint; reads as "improving" in the Green/Yellow/Red analysis language

**Visual language**
- Rounded cards (20–24pt corner radius), soft inner shadows, glassmorphism on hero surfaces.
- Cinematic transitions for capture flow, baseline reveal, before/after slider, paywall reveal.
- Single-stroke charts with mint accent on dark; no multi-color clutter.
- Region body diagrams styled like Apple Health anatomy — soft, anatomical, not gym-poster.
- Typography: SF Pro / SF Pro Rounded for numerics; generous tracking on hero metrics.
- Honest-feedback components: neutral and red states are first-class UI, not buried.

### First screens to build
1. Onboarding welcome carousel + consistency education
2. Profile + optional measurements
3. Home dashboard (Progress Score hero + weekly summary)
4. Guided capture screen with silhouette overlay
5. AI analysis screen with region body diagram

### Build mode
Mock-first, fully local. No backend, no live AI, no live billing in v1. Ready to layer real services later.