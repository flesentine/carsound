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
  - new reusable TargetFrequencyEnergyMeter
  - measurement uses the Balanced smoothed spectrum
  - evaluates a narrow multi-bin band centered on the selected cancellation target
  - band half-width is at least 8 Hz and otherwise scales to 1.5 FFT bins
  - band energy is summed in linear power rather than averaging dB values
  - center-frequency level is estimated separately using linear-power interpolation between neighboring FFT bins
  - nearest FFT-bin frequency is reported for transparency
  - matching noise-floor bins are summed across the same band
  - dB above the tracked floor is reported when complete floor data is available
  - incomplete floor data is shown as warming up rather than fabricated
  - Cancellation Lab now has a live Target Energy card
  - live card shows narrow-band energy, center level, floor energy, dB above floor, measured target, nearest FFT bin, actual band limits/bin count, and FFT resolution
  - measurement is calculated from the published capture snapshot, keeping this UI work out of the audio callback
  - UI explicitly says lower narrow-band energy means less measured energy near the selected target
  - UI warns that phone position, route, stereo volume, and driving condition must stay consistent for meaningful comparisons
  - tests cover multi-bin band selection, linear-power summation, 10 dB spectrum/floor separation, incomplete-floor handling, and power-domain interpolation
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
- [ ] #17 Create before/after measurement
- [ ] #18 Add experiment recorder
- [ ] #19 Add automatic phase sweep
- [ ] #20 Refine phase search
- [ ] #21 Add automatic amplitude search
- [ ] #22 Build adaptive controller

## Verification note

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. CI currently uses `build-for-testing`, so it compiles the unit tests but does not execute them. Target-frequency energy is a relative digital FFT-band measurement, not calibrated acoustic SPL. Physical iPhone/car testing is still required to determine whether phase changes actually reduce the measured cabin tone in a repeatable way.
