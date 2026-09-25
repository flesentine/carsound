# QuietDrive Lab status

## Completed

- [x] #1 Create native iOS project scaffold
  - SwiftUI app shell
  - microphone permission flow
  - privacy description
  - unit-test target
  - GitHub Actions build workflow
- [x] #2 Set up audio session
  - simultaneous playback + recording (`playAndRecord`)
  - measurement mode for reduced system signal processing
  - mixes with other audio
  - Bluetooth A2DP output enabled
  - built-in speaker fallback
  - preferred 48 kHz sample rate and 5 ms I/O buffer request
  - live input/output route inspection
  - Bluetooth/car/USB route labels
  - route-change notifications
  - media-services reset handling
  - activate/deactivate/reconfigure controls
  - actual sample-rate and I/O-buffer diagnostics
- [x] #3 Build microphone capture
  - real-time `AVAudioEngine` microphone input
  - 1,024-frame PCM input tap
  - start/stop/reset capture controls
  - buffer and frame counters
  - actual capture sample rate, channel count, and PCM format
  - thread-safe capture metadata handoff from the audio callback
  - audio buffers observed in memory and never written to disk
  - capture automatically stops before audio-session reconfiguration/deactivation
- [x] #4 Build raw audio diagnostics screen
  - live RMS and peak signal levels
  - dBFS conversion, meters, peak hold, and headroom
  - clipping detection and counts
  - actual buffer size and duration
  - unit coverage for dBFS and meter math
- [x] #5 Implement FFT processing
  - rolling 4,096-sample analysis window
  - Hann window before every transform
  - radix-2 FFT implementation
  - full 0 Hz-to-Nyquist spectrum in dBFS
  - ~11.72 Hz/bin resolution at 48 kHz
  - synthetic known-frequency sine-wave test source
  - app and unit-test targets compiled in CI
- [x] #6 Build live spectrum graph
  - SwiftUI Canvas-based live spectrum
  - 20–200 Hz low-frequency view
  - optional 20–2,000 Hz context view
  - frequency and dBFS axes
  - raw unsmoothed FFT display
  - graph coordinate/range tests
- [x] #7 Add spectrum smoothing
  - raw FFT remains preserved and independently viewable
  - temporal exponential smoothing in linear power
  - Responsive, Balanced, and Stable presets
  - smoothing limited to 0–2,000 Hz
  - Raw / Smoothed comparison control
  - full app + unit-test simulator build-for-testing green
- [x] #8 Implement noise-floor measurement
  - adaptive per-frequency background floor from 20–2,000 Hz
  - low-frequency and wideband floor estimates
  - dB-above-floor measurements
  - per-bin floor spectrum retained
  - full app + unit-test simulator build-for-testing green
- [x] #9 Build dominant-frequency detection
  - analyzes the Balanced smoothed 20–200 Hz spectrum
  - detects and ranks locally prominent low-frequency peaks
  - combines local prominence with temporal floor excess
  - frequency interpolation beyond raw FFT-bin centers
  - nearby duplicate suppression
  - full app + unit-test simulator build-for-testing green
- [x] #10 Add persistent-tone detection
  - tracks dominant-frequency candidates across the audio-sample timeline
  - frequency matching tolerance keeps the same physical tone attached to one track
  - brief candidate dropouts are tolerated without immediately losing a track
  - stale tracks expire after a configurable gap
  - persistence requires at least 2 seconds by default
  - persistence also requires minimum presence ratio and frequency stability
  - running mean frequency and sample standard deviation measure stability
  - average local prominence and average temporal floor excess retained per tone
  - confidence score combines duration, presence, frequency stability, and spectral strength
  - Low / Medium / High confidence labels
  - UI shows duration, presence %, frequency standard deviation, average prominence, average floor excess, confidence, observations, and Persistent/Building state
  - tracker time is derived from captured audio duration rather than wall-clock UI timing
  - tracker resets with capture reset
  - deterministic tests cover 2-second persistence, brief dropouts, expiration after long gaps, unstable frequency rejection, and low-presence rejection
  - full app + unit-test simulator build-for-testing green in GitHub Actions

## Next

- [ ] #11 Add low-frequency-only analysis mode
- [ ] #12 Build tone generator
- [ ] #13 Add manual output-level control
- [ ] #14 Add manual phase control
- [ ] #15 Build Lab cancellation control screen
- [ ] #16 Measure target-frequency energy
- [ ] #17 Create before/after measurement
- [ ] #18 Add experiment recorder
- [ ] #19 Add automatic phase sweep
- [ ] #20 Refine phase search

## Verification note

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. CI currently uses `build-for-testing`, so it compiles the unit tests but does not execute them. Physical microphone and vehicle-route behavior still require a real iPhone/car test. Noise-floor, spectrum, dominant-frequency, and persistence measurements are digital/relative values, not calibrated SPL.
