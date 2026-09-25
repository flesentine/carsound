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
  - temporal exponential smoothing performed in linear power, not directly in dB
  - Responsive, Balanced, and Stable smoothing presets
  - all three smoothing states maintained independently so switching presets is immediate
  - smoothing limited to 0–2,000 Hz to reduce real-time audio-callback work
  - Raw / Smoothed comparison control in the Lab UI
  - default display uses Balanced smoothing
  - preset descriptions explain responsiveness tradeoffs
  - graph label reflects the active raw/smoothing mode
  - smoothing reset is tied to capture reset
  - tests cover first-frame seeding, relative preset responsiveness, and 2 kHz analysis-band limit
  - full app + unit-test simulator build-for-testing green in GitHub Actions

## Next

- [ ] #8 Implement noise-floor measurement
- [ ] #9 Build dominant-frequency detection
- [ ] #10 Add persistent-tone detection

## Verification note

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. Physical microphone and vehicle-route behavior still require a real iPhone/car test. Spectrum magnitudes are digital dBFS values, not calibrated SPL.
