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
  - manual 0–360 degree phase setting
  - phase normalized modulo one full cycle
  - quick 0°, 90°, 180°, and 270° presets
  - dedicated Invert +180° control
  - generated PCM loop includes the selected phase offset
  - phase does not alter the selected frequency or hard-capped amplitude
  - integer-Hz one-second loop remains phase-continuous at its wrap boundary for arbitrary fixed phase
  - live phase changes are supported while tone playback is active
  - live phase slider changes are debounced to avoid repeatedly rebuilding the tone buffer during fast dragging
  - active live phase changes ramp output down over 35 ms, swap the phase-shifted loop, then ramp back up over 35 ms
  - muted playback remains muted across phase changes
  - immediate MUTE NOW behavior remains available
  - UI reports the current phase and live phase transition time
  - tests cover phase normalization, +180° inversion, 90° positive-peak start, waveform inversion at 180°, and phased-loop wrap continuity
  - fixed Swift 6 async/concurrency overload issues found by CI in the live buffer-swap path
  - full app + unit-test simulator build-for-testing green in GitHub Actions

## Milestone status

### Milestone 1 — Hear the car
- [x] #1–#11 complete

### Milestone 2 — Fight one frequency
- [x] #12 Build tone generator
- [x] #13 Add manual output-level control
- [x] #14 Add manual phase control
- [ ] #15 Build Lab cancellation control screen
- [ ] #16 Measure target-frequency energy
- [ ] #17 Create before/after measurement
- [ ] #18 Add experiment recorder
- [ ] #19 Add automatic phase sweep
- [ ] #20 Refine phase search
- [ ] #21 Add automatic amplitude search
- [ ] #22 Build adaptive controller

## Verification note

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. CI currently uses `build-for-testing`, so it compiles the unit tests but does not execute them. Physical iPhone verification is especially important for generated output: Bluetooth/car-route latency and jitter mean a user-selected digital phase is not yet proven to equal the acoustic phase arriving at the phone microphone. That relationship will be measured experimentally in later milestones.
