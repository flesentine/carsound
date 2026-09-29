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
  - dedicated Cancellation Lab screen linked from the main Lab
  - experiment-readiness panel for audio session, ANC Focus mode, input route, and output route
  - focused target-frequency slider for 30–200 Hz cancellation work
  - can adopt the highest-confidence persistent tone as the generator target
  - centralized manual output-level control
  - centralized 0–360 degree phase control
  - 0°, 90°, 180°, and 270° phase presets
  - Invert +180° control
  - separate Start/Stop Capture control
  - separate Start/Stop Tone control
  - combined Start Capture + Tone control
  - Stop All control
  - dedicated MUTE NOW / Resume safety control
  - live state summary for microphone, generator, target frequency, phase, output level, and persistent-tone count
  - input/output route summaries visible before running the experiment
  - hard digital ceiling remains visible in the safety section
  - screen explicitly does not claim cancellation effectiveness yet; objective target-energy measurement begins in #16
  - main Lab now displays a Cancellation Lab launch card and readiness indicator
  - full app + unit-test simulator build-for-testing green in GitHub Actions

## Milestone status

### Milestone 1 — Hear the car
- [x] #1–#11 complete

### Milestone 2 — Fight one frequency
- [x] #12 Build tone generator
- [x] #13 Add manual output-level control
- [x] #14 Add manual phase control
- [x] #15 Build Lab cancellation control screen
- [ ] #16 Measure target-frequency energy
- [ ] #17 Create before/after measurement
- [ ] #18 Add experiment recorder
- [ ] #19 Add automatic phase sweep
- [ ] #20 Refine phase search
- [ ] #21 Add automatic amplitude search
- [ ] #22 Build adaptive controller

## Verification note

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. CI currently uses `build-for-testing`, so it compiles the unit tests but does not execute them. The Cancellation Lab is now structurally ready for a physical experiment, but it still does not measure whether generated output actually reduces cabin noise. Bluetooth/car-route latency, acoustic phase, real speaker loudness, and simultaneous input/output behavior still require real-device testing.
