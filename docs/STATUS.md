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
  - UI updates throttled away from the real-time audio callback
  - audio buffers observed in memory and never written to disk
  - capture automatically stops before audio-session reconfiguration/deactivation
  - full iOS simulator build green in GitHub Actions

## Next

- [ ] #4 Build raw audio diagnostics screen
- [ ] #5 Implement FFT processing
- [ ] #6 Build live spectrum graph
- [ ] #7 Add spectrum smoothing
- [ ] #8 Implement noise-floor measurement
- [ ] #9 Build dominant-frequency detection
- [ ] #10 Add persistent-tone detection

## Verification note

The app compiles successfully in GitHub Actions against the iOS simulator SDK. Physical microphone and vehicle-route behavior still require a real iPhone/car test.
