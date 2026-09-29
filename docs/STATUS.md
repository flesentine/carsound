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
- [x] #19 Add automatic phase sweep
  - new reusable PhaseSweepModel
  - default coarse sweep tests 8 phases: 0°, 45°, 90°, 135°, 180°, 225°, 270°, and 315°
  - phase inputs are normalized modulo 360° and duplicate phase values are removed
  - one previously captured baseline is reused across the full sweep
  - target frequency and output level remain fixed across the sweep
  - each phase gets a 350 ms settling interval after phase application
  - each phase then collects 20 valid target-energy readings at 10 Hz
  - treatment windows are averaged in linear power through the existing before/after math
  - every phase is compared against the same baseline
  - every completed phase comparison is automatically saved to durable experiment history
  - sweep progress reports phase index, phase angle, settling state, and sample count
  - sweep results table shows phase, treatment target-band energy, and reduction/increase relative to baseline
  - best coarse phase is selected by lowest measured treatment-band energy
  - treatment variability is used as a tie-breaker when energies are effectively equal
  - Apply Best Coarse Phase control
  - sweep automatically mutes generated output after all phases finish
  - Cancel Sweep immediately cancels the active sweep and mutes tone output
  - MUTE NOW cancels the sweep before muting
  - Stop All cancels both A/B measurement and phase sweep before stopping tone/capture
  - target/phase/output and conflicting experiment controls are locked during a sweep
  - coarse sweep reset preserves durable experiment history while clearing the live sweep table
  - tests cover default phase grid, phase normalization/deduplication, best-energy selection, and variability tie-breaking
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
- [x] #19 Add automatic phase sweep
- [ ] #20 Refine phase search
- [ ] #21 Add automatic amplitude search
- [ ] #22 Build adaptive controller

## Verification note

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. CI currently uses `build-for-testing`, so it compiles the unit tests but does not execute them. The automatic sweep identifies the lowest measured point on a coarse 45° digital-phase grid; it is not yet a fine optimum and does not establish the acoustic phase at the phone microphone. Physical iPhone/car testing remains required.
