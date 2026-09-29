# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#16 — target-frequency energy measurement** is implemented.

The Cancellation Lab now reports live energy around the selected target frequency instead of relying only on the spectrum graph or listening by ear.

The meter uses the **Balanced** smoothed spectrum and measures a small multi-bin band around the target. Energy is summed in **linear power** and converted back to dB, which is more appropriate than averaging dB values directly. It also reports a separately interpolated center-frequency level, the nearest FFT bin, the exact measured band, and the matching tracked noise-floor energy.

When floor data is available, the Lab shows **dB above floor** for the target band. This makes phase experiments observable in real time: if the same target, phone position, route, vehicle volume, and operating condition are held steady, a lower narrow-band energy indicates less measured energy near that frequency.

This is still a live measurement only. **#17 — before/after measurement** adds a controlled baseline-versus-treatment comparison so the app can quantify the change instead of making the user compare moving numbers manually.

## Privacy principle

Raw microphone audio is not stored. Live microphone buffers are reduced in memory to measurements such as level, spectrum, noise floor, candidate frequencies, persistence metrics, and target-band energy.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
