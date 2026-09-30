# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#27 — Bluetooth jitter diagnostics** is implemented.

QuietDrive can now run a live Bluetooth timing window instead of relying on one static route snapshot.

A jitter run samples the active path every **250 ms** for up to **120 fresh samples**, roughly 30 seconds. Each accepted sample records:

- a monotonic elapsed timestamp
- FFT transform sequence
- active Bluetooth profile
- route revision
- sample rate
- I/O buffer duration
- iOS input/output latency
- latest microphone callback interval
- estimated spectrum-center age

A sample is accepted only when the FFT sequence advances. Reading the same published spectrum repeatedly does not count as fresh timing evidence. If fresh FFT measurements stop arriving for roughly three seconds, the run fails rather than producing a falsely stable result.

The live summary calculates:

- callback timing mean, jitter, and range
- spectrum-center age mean, jitter, and range
- iOS-reported output-latency mean, jitter, and range
- route-revision changes
- Bluetooth-profile changes
- I/O-buffer changes
- sample-rate changes

The UI labels the observation as **Insufficient data**, **Stable observed timing**, **Variable observed timing**, or **Unstable observed timing**. Configuration changes automatically make the observed window unstable; timing thresholds then distinguish small versus larger variation when the route remains unchanged.

These labels are deliberately limited to what the phone can observe. iOS does not expose per-packet Bluetooth codec/head-unit delay, so QuietDrive does **not** present these numbers as direct Bluetooth transport jitter or acoustic round-trip jitter.

## Verification status

The app and unit-test targets compile successfully in GitHub Actions using the iOS simulator SDK. CI uses `build-for-testing`, so tests compile but are not executed there.

Useful Bluetooth jitter data still requires physical iPhone/head-unit testing. A route may look stable in these diagnostics yet still have unmeasured transport or acoustic delay that matters for phase cancellation.

## What comes next

**#28 — accelerometer capture** is next. That starts the vibration side of Milestone 3 so QuietDrive can compare cabin sound against vehicle/body vibration rather than relying on microphone data alone.

## Privacy principle

Raw microphone audio is not stored. Bluetooth jitter diagnostics retain only live timing and route metadata in memory for the current diagnostic window.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
