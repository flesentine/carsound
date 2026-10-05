# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#33 — calibration** is implemented. This begins **Milestone 4 — Prove it**.

QuietDrive can now create durable, route-specific calibration profiles before controlled vehicle experiments.

A calibration run captures a **5-second quiet reference** from 50 fresh paired microphone and accelerometer observations. Calibration requires the audio session, microphone, and accelerometer to be active, and QuietDrive's generated tone must be stopped or muted. Clipping, likely program-audio interference, capture loss, or an audio-route change aborts the run instead of saving a compromised profile.

Each saved calibration profile records:

- route family, route signature, and route revision
- input/output route descriptions
- sample rate and I/O buffer duration
- iOS-reported input/output latency
- average microphone RMS in dBFS
- microphone RMS variability
- low-frequency and wideband noise floors
- current target-band reference energy when available
- accelerometer X/Y/Z orientation/gravity baseline
- dynamic vibration RMS
- observed accelerometer sample rate and timing jitter
- microphone callback jitter
- estimated spectrum-center age
- maximum program-audio interference score seen during calibration

QuietDrive averages dB measurements in **linear power** before converting them back to dB.

### Optional external SPL reference

The Calibration card accepts an optional simultaneous reading from an external sound meter.

When provided, QuietDrive stores an approximate offset between the phone's measured RMS dBFS and that external reference. That offset is only used when the **same route signature** is active.

This is deliberately labeled **approximate SPL**, not calibrated dBA. QuietDrive does not apply certified A/C weighting, microphone sensitivity certification, or laboratory traceability.

Without an external reference, absolute SPL remains unavailable and the native acoustic measurements stay in dBFS.

### Route matching

Calibration profiles are never blindly reused.

A profile is considered a live match only when:

- the route signature is identical
- the active sample rate is within 1 Hz of the saved profile

Changing the input/output path therefore removes the active calibration match instead of applying the wrong reference.

Calibration profiles are stored locally as atomic JSON and can be individually deleted or cleared.

## Verification status

The app and unit-test targets compile successfully in GitHub Actions using the iOS simulator SDK. CI uses `build-for-testing`, so tests compile but are not executed there.

Calibration math/persistence coverage includes linear-power dB averaging, external SPL offsets, route guarding, sample-rate matching, external-reference validation, and durable save/reload/delete.

Useful calibration values still require a physical iPhone and the actual audio route that will be used for the vehicle experiment.

## What comes next

**#34 — structured logs** is next.

The remaining Milestone 4 roadmap is:

- #34 structured logs
- #35 CSV/JSON export
- #36 test dashboard
- #37 repeatability
- #38 head-position sensitivity
- #39 multiple frequencies
- #40 Lab go/no-go report

## Privacy principle

Raw microphone audio is not stored. Raw accelerometer samples remain in memory only. Calibration stores derived route, timing, acoustic, and motion summary values locally.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
