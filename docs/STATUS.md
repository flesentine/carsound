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
  - new reusable before/after measurement model
  - baseline and treatment are measured as windows rather than single FFT frames
  - each window collects 20 valid target-energy samples at 10 Hz
  - 350 ms settling delay before each window begins
  - window averages are calculated in linear power before converting back to dB
  - baseline capture automatically mutes generated output if it is currently audible
  - baseline can also be captured with the tone already stopped/muted
  - treatment capture requires the generated tone to be actively playing and unmuted
  - treatment is disabled if the target frequency changed after baseline
  - changing target requires a fresh baseline
  - baseline capture clears any previous treatment result
  - comparison reports treatment-minus-baseline dB and measured reduction dB
  - positive measured reduction means less target-band energy in treatment than baseline
  - window summaries retain target frequency, phase, output level, tone state, sample count, duration, min/max energy, center level, and variability
  - Cancellation Lab shows baseline and treatment averages plus standard deviation
  - live progress shows settling and sample collection count
  - target/phase/output controls are locked during a measurement window
  - ordinary start/stop experiment controls are locked during a measurement window
  - MUTE NOW remains available during measurement
  - Stop All cancels any active comparison window and stops tone/capture
  - comparison capture is generation-cancellable so stale async collection cannot overwrite a reset state
  - tests cover power-domain window averaging, positive reduction, measured increase, target mismatch rejection, and mixed-target sample rejection
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
- [ ] #18 Add experiment recorder
- [ ] #19 Add automatic phase sweep
- [ ] #20 Refine phase search
- [ ] #21 Add automatic amplitude search
- [ ] #22 Build adaptive controller

## Verification note

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. CI currently uses `build-for-testing`, so it compiles the unit tests but does not execute them. Before/after values are relative digital target-band measurements, not calibrated acoustic SPL. Meaningful physical comparisons still require a real iPhone/car test with stable phone position, route, vehicle volume, and driving conditions.
