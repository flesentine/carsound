# QuietDrive Lab status

## Completed

- [x] #1 Create native iOS project scaffold
- [x] #2 Set up audio session
- [x] #3 Build microphone capture
- [x] #4 Build raw audio diagnostics screen
- [x] #5 Implement FFT processing
- [x] #6 Build live spectrum graph
- [x] #7 Add spectrum smoothing
- [x] #8 Implement noise-floor measurement
- [x] #9 Build dominant-frequency detection
- [x] #10 Add persistent-tone detection
- [x] #11 Add low-frequency-only analysis mode
- [x] #12 Build tone generator
- [x] #13 Add manual output-level control
- [x] #14 Add manual phase control
- [x] #15 Build Lab cancellation control screen
- [x] #16 Measure target-frequency energy
- [x] #17 Create before/after measurement
- [x] #18 Add experiment recorder
  - durable local experiment history
  - experiment records stored as JSON under Application Support
  - no raw microphone audio is stored
  - each saved run records timestamp, target frequency, treatment phase, treatment output level, baseline energy, treatment energy, treatment-minus-baseline dB, measured reduction dB, center levels, baseline/treatment variability, sample counts, window durations, input route, and output route
  - Save Run button appears after a completed A/B comparison
  - accidental repeat saving of the same displayed comparison is disabled within the active comparison state
  - saved runs are displayed newest-first in the Cancellation Lab
  - history shows phase/output/target, reduction or increase, baseline/treatment values, variability, sample counts, route summaries, and timestamp
  - per-run Delete Run control
  - Clear All Saved Runs control
  - history view shows the 20 most recent runs while preserving all saved records locally
  - recorder errors are surfaced in the Lab UI instead of silently discarding failures
  - JSON writes use atomic replacement
  - history reloads automatically when the recorder model initializes
  - persistence tests use temporary JSON files and cover save/reload, field capture, delete persistence, and clear-all persistence
  - fixed an optional-value test compile issue found by CI
  - full app + unit-test simulator build-for-testing green in GitHub Actions

## Milestone status

### Milestone 1 — Hear the car
- [x] #1–#11 complete

### Milestone 2 — Fight one frequency
- [x] #12 Build tone generator
- [x] #13 Add manual output-level control
- [x] #14 Add manual phase control
- [x] #15 Build Lab cancellation control screen
- [x] #16 Measure target-frequency energy
- [x] #17 Create before/after measurement
- [x] #18 Add experiment recorder
- [ ] #19 Add automatic phase sweep
- [ ] #20 Refine phase search
- [ ] #21 Add automatic amplitude search
- [ ] #22 Build adaptive controller

## Verification note

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. CI currently uses `build-for-testing`, so it compiles the unit tests but does not execute them. Saved experiments contain relative digital measurement summaries, not calibrated acoustic SPL and not raw audio. Physical iPhone/car testing remains necessary before interpreting reductions as repeatable acoustic cancellation.
