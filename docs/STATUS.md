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
  - 20–200 Hz sine-wave generation
  - integer-Hz frequency control
  - one-second phase-continuous PCM loop
  - AVAudioPlayerNode playback through a dedicated AVAudioEngine
  - mono generator connected through the engine main mixer
  - output sample rate follows the active hardware/output route
  - fixed conservative sample amplitude of 0.01 for this milestone
  - fixed digital level of approximately -40 dBFS
  - 120 ms software fade-in and fade-out to reduce start/stop clicks
  - manual amplitude adjustment intentionally deferred to #13
  - frequency changes disabled while tone playback is active
  - tone output requires an already-active play-and-record audio session
  - audio-session reconfigure/deactivate immediately mutes and stops the tone
  - Lab UI shows frequency, fixed amplitude, fixed dBFS level, ramp duration, render sample rate, and loop-buffer frames
  - tests cover frequency clamping/rounding, one-second loop length, amplitude ceiling, loop-wrap phase continuity, and fixed -40 dBFS level
  - full app + unit-test simulator build-for-testing green in GitHub Actions

## Milestone status

### Milestone 1 — Hear the car
- [x] #1–#11 complete

### Milestone 2 — Fight one frequency
- [x] #12 Build tone generator
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

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. CI currently uses `build-for-testing`, so it compiles the unit tests but does not execute them. Physical iPhone verification is now especially important: simultaneous microphone capture plus generated output, Bluetooth/car routing, actual acoustic level, and click-free ramps cannot be validated by simulator CI. Generated-tone digital level is not a calibrated acoustic SPL.
