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
  - rolling 4,096-sample analysis window fed by the existing 1,024-frame microphone callbacks
  - Hann window before every transform
  - radix-2 FFT implementation
  - multi-channel input downmixed to mono for spectral analysis
  - full 0 Hz-to-Nyquist spectrum produced in dBFS
  - normalized magnitude calculation that accounts for Hann-window coherent gain
  - finite -140 dBFS spectrum floor
  - ~11.72 Hz/bin resolution at 48 kHz
  - FFT size, resolution, bin count, Nyquist, window, and transform count exposed in the Lab UI
  - synthetic known-frequency sine-wave test source added
  - CI upgraded to compile both the app and unit-test targets
  - full simulator build-for-testing green in GitHub Actions

## Next

- [ ] #6 Build live spectrum graph
- [ ] #7 Add spectrum smoothing
- [ ] #8 Implement noise-floor measurement
- [ ] #9 Build dominant-frequency detection
- [ ] #10 Add persistent-tone detection

## Verification note

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. Physical microphone and vehicle-route behavior still require a real iPhone/car test. Spectrum magnitudes are digital dBFS values, not calibrated SPL.
