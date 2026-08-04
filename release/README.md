# Release

Versioned release notes and build manifest.

- `CHANGELOG.md` — append-only, human-readable release history. This is
  what you paste into App Store release notes.
- `versions/<semver>.md` — per-version detail (1.0.0.md, 1.1.0.md, …)
- `builds/<number>.json` — what each archived build was: scheme, version,
  build number, TestFlight + App Store status
