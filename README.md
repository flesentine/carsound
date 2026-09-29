# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#24 — processing latency** is implemented.

QuietDrive now measures the timing of its own microphone/analysis path instead of treating latency as one opaque number.

The live Processing Latency panel reports:

- microphone buffer duration
- latest microphone callback interval
- rolling average callback interval
- callback jitter (standard deviation)
- minimum/maximum callback interval
- latest analysis/DSP processing time
- rolling average processing time
- maximum observed processing time
- FFT analysis-window duration
- age of the latest analyzed snapshot when it is published
- estimated age of the **center of the FFT time window** at publication

For the current 4096-sample FFT at 48 kHz, the analysis window itself spans about **85.33 ms**. QuietDrive therefore reports that time support explicitly instead of implying the spectrum is instantaneous.

The app also now exposes iOS's route-reported:

- I/O buffer duration
- input latency
- output latency

Those values are shown separately from measured app/DSP timing. They are useful diagnostics, but they are **not yet a measured Bluetooth or acoustic round-trip delay**. Route-specific and Bluetooth timing work remains in #25–#27.

The latency instrumentation uses monotonic uptime timestamps inside the microphone callback path and rolling statistics, so it can reveal whether timing instability comes from callback cadence, DSP work, or snapshot-publication age.

## Verification status

The app and unit-test targets compile successfully in GitHub Actions using the iOS simulator SDK. CI uses `build-for-testing`, so tests compile but are not executed there.

Simulator timing does not represent a real iPhone/car audio route. The useful numbers from #24 must be collected on physical hardware before drawing conclusions about cancellation feasibility.

## What comes next

**#25 — audio-route testing** is next. That will make route identity/configuration a first-class experiment dimension so built-in speaker, wired/USB/CarPlay, Bluetooth, and car-audio paths can be characterized separately.

## Privacy principle

Raw microphone audio is not stored. Live microphone buffers are reduced in memory to measurements such as level, spectrum, noise floor, persistence, target-band energy, search/controller state, stability diagnostics, latency diagnostics, and saved experiment metadata.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
