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
  - live 0–100% output slider
  - hard PCM sample-amplitude ceiling of 0.02
  - maximum digital tone level is approximately -34 dBFS
  - default output is 50% of the hard ceiling
  - default effective amplitude remains 0.01 / approximately -40 dBFS, matching milestone #12
  - generated PCM buffer is always bounded by the hard maximum
  - player-node gain scales the generated buffer within the hard ceiling
  - live level changes use a 60 ms ramp
  - start and stop retain the existing 120 ms ramp
  - immediate MUTE NOW control zeros player output without waiting for a ramp
  - Resume restores the selected level with a short ramp
  - selected output can be changed while the tone is playing
  - selected amplitude, selected dBFS level, hard maximum amplitude, hard dBFS ceiling, and ramp times shown in the Lab UI
  - digital ceiling explicitly documented as not equivalent to acoustic SPL; car stereo volume still matters
  - audio-session reconfigure/deactivate still immediately mutes and stops tone output
  - tests cover output-percentage clamping, retained -40 dBFS default, hard 0.02 amplitude ceiling, approximately -33.98 dBFS maximum, and finite silence-floor behavior
  - full app + unit-test simulator build-for-testing green in GitHub Actions

## Milestone status

### Milestone 1 — Hear the car
- [x] #1–#11 complete

### Milestone 2 — Fight one frequency
- [x] #12 Build tone generator
- [x] #13 Add manual output-level control
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

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. CI currently uses `build-for-testing`, so it compiles the unit tests but does not execute them. Physical iPhone verification is especially important for generated output: the digital hard ceiling does not establish a safe or calibrated acoustic sound level at the car speakers. Simultaneous microphone capture, Bluetooth/car routing, acoustic output, and click-free ramps still require real-device testing.
