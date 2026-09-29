# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#25 — audio-route testing** is implemented.

QuietDrive can now save durable, route-specific diagnostic snapshots instead of mixing measurements from different audio paths.

The app distinguishes these route families:

- Built-in
- Wired analog
- USB audio
- Car audio
- Bluetooth A2DP
- Bluetooth HFP
- Bluetooth LE
- AirPlay
- HDMI
- Mixed / unknown configurations

Bluetooth A2DP, HFP, and LE are deliberately kept separate because their behavior can differ substantially.

Each saved route test records:

- route family
- stable input/output route signature
- route-revision number
- input/output port descriptions
- sample rate
- actual I/O buffer duration
- iOS-reported input/output latency
- microphone buffer duration
- callback cadence and jitter
- DSP processing timing
- FFT-window duration
- snapshot age
- estimated spectrum-center age
- buffer and FFT-transform counts

Route signatures use port type and displayed name, sorted for stability, and do not persist raw AVAudioSession port UIDs.

The Cancellation Lab now has an **Audio Route Testing** panel with a live route summary, Refresh Route, Capture Route Test, durable newest-first history, distinct-route count, per-record delete, and clear-all controls.

A route test requires an active audio session, active microphone capture, valid input/output routes, and at least one completed FFT transform so timing fields are meaningful.

## Verification status

The app and unit-test targets compile successfully in GitHub Actions using the iOS simulator SDK. CI uses `build-for-testing`, so tests compile but are not executed there.

The simulator can verify the route-testing code path, but useful route records must be captured on a physical iPhone with the real connection types you want to compare.

Route tests still do **not** measure end-to-end acoustic round-trip latency. They create the controlled route dataset needed for the Bluetooth-specific characterization in #26 and jitter diagnostics in #27.

## What comes next

**#26 — Bluetooth behavior** is next. With route identity now explicit, QuietDrive can characterize what actually changes when the output path is A2DP/HFP/LE instead of built-in, USB, or car audio.

## Privacy principle

Raw microphone audio is not stored. Route testing stores diagnostic metadata such as port display names/types, timing measurements, sample rate, and processing statistics; it does not persist raw AVAudioSession port UIDs.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
