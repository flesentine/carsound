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
  - detects local spectral maxima instead of simply choosing the loudest FFT bin
  - compares each candidate against both the tracked temporal floor and its local spectral neighborhood
  - avoids missing a steady tone that was already present when the noise-floor estimator initialized
  - requires minimum local prominence before reporting a candidate
  - ranks candidates using local prominence plus temporal floor excess
  - suppresses nearby duplicate peaks with a configurable minimum frequency separation
  - quadratic/parabolic interpolation refines peak frequency beyond the raw FFT-bin center
  - returns up to five ranked low-frequency candidates
  - UI shows frequency, dBFS magnitude, local prominence, and temporal floor excess
  - explicitly remains instantaneous; persistence/confidence-over-time is deferred to #10
  - tests cover clear-peak detection, startup-floor peak detection, flat-spectrum rejection, peak separation, and 20–200 Hz range limits
  - full app + unit-test simulator build-for-testing green in GitHub Actions

## Next

- [ ] #10 Add persistent-tone detection

## Verification note

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. Physical microphone and vehicle-route behavior still require a real iPhone/car test. Noise-floor, spectrum, and dominant-frequency measurements are digital dBFS/relative values, not calibrated SPL.
