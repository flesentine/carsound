# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#8 — noise-floor measurement** is implemented.

The Lab now tracks an adaptive spectral background floor from **20–2,000 Hz**. The estimator works in linear power, falls toward quieter conditions relatively quickly, and rises toward louder conditions slowly so a short transient does not instantly become the new baseline.

The UI reports separate **20–200 Hz** and **20–2,000 Hz** floor values along with how many dB the current spectrum sits above those baselines. The per-frequency floor spectrum is also retained for the dominant-frequency and persistent-tone work that follows.

These measurements are digital dBFS references, not calibrated acoustic SPL.

## Privacy principle

Raw microphone audio is not stored. Live microphone buffers are reduced in memory to measurements such as level, spectrum, background floor, frequency peaks, and confidence values.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
