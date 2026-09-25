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

## Next

- [ ] #3 Build microphone capture
- [ ] #4 Build raw audio diagnostics screen
- [ ] #5 Implement FFT processing
- [ ] #6 Build live spectrum graph
- [ ] #7 Add spectrum smoothing
- [ ] #8 Implement noise-floor measurement
- [ ] #9 Build dominant-frequency detection
- [ ] #10 Add persistent-tone detection

## Verification note

Source-level checks can run anywhere, but an actual iOS build and route test require Xcode/iOS hardware. GitHub Actions is configured to perform the Xcode build once the repository contains the project.
