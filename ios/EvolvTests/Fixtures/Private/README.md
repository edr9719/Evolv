# Private Evolv fixtures

Place consented real-person fixture sets here. Everything in this directory except this README is ignored by Git and must never be added to the Evolv app target.

Each fixture set needs a `manifest.json` with these fields for every image:

- `pseudonymousSubject`
- `scanDate`
- `pose`
- `consentClassification`
- `expectedCondition`
- `transformation`
- `device`
- `environment`

The test runner stages this directory into a temporary test bundle and removes the staging copy when the run finishes.
