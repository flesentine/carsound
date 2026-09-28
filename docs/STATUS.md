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
  - new selectable Analysis Mode with ANC Focus and Wide Lab
  - ANC Focus is the default mode
  - ANC Focus narrows downstream analysis to 30–200 Hz
  - Wide Lab retains 20–2,000 Hz diagnostic context
  - the 4,096-sample FFT remains intact; filtering happens after the transform
  - smoothing now receives only bins inside the selected analysis band
  - adaptive noise-floor tracking operates only on the selected band
  - dominant-frequency detection honors the active mode's frequency range
  - persistent-tone tracking receives only candidates from the active mode
  - mode switching is disabled during active capture so state cannot mix across bands
  - changing modes resets analysis state before the next capture
  - raw spectrum display is also filtered to the active downstream band
  - dedicated 30–200 Hz graph range added
  - UI reports the active downstream and dominant-detection ranges
  - regression tests cover ANC-band filtering, Wide Lab filtering, smoothing-band filtering, dominant-detector lower-bound enforcement, and the 30–200 Hz graph scale
  - fixed a Swift 6 default-argument compile issue found by CI
  - full app + unit-test simulator build-for-testing green in GitHub Actions

## Milestone status

### Milestone 1 — Hear the car
- [x] #1–#11 complete

### Milestone 2 — Fight one frequency
- [ ] #12 Build tone generator
- [ ] #13 Add manual output-level control
- [ ] #14 Add manual phase control
- [ ] #15 Build Lab cancellation control screen
- [ ] #16 Measure target-frequency energy
- [ ] #17 Create before/after measurement
- [ ] #18 Add experiment recorder
- [ ] #19 Add automatic phase sweep
- [ ] #20 Refine phase search
- [ ] #21 Add automatic amplitude search
- [ ] #22 Build adaptive controller

## Verification note

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. CI currently uses `build-for-testing`, so it compiles the unit tests but does not execute them. Physical microphone, Bluetooth, and vehicle-route behavior still require a real iPhone/car test. Noise-floor, spectrum, dominant-frequency, and persistence measurements are digital/relative values, not calibrated SPL.
