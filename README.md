# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#15 — Lab cancellation control screen** is implemented.

The app now has a dedicated **Cancellation Lab** instead of forcing the experimenter to jump between diagnostic cards. The screen centralizes the controls needed for the first manual cancellation tests:

- audio/input/output readiness
- 30–200 Hz target frequency
- highest-confidence persistent-tone targeting
- manual output level
- manual 0–360° phase
- phase presets and +180° inversion
- microphone capture controls
- tone-generator controls
- combined Start Capture + Tone
- Stop All
- immediate MUTE NOW / Resume
- live generator and microphone state

The screen intentionally does **not** report whether a phase setting improved the target noise yet. That begins with **#16 — target-frequency energy measurement**, which will provide an objective measurement at the selected frequency rather than relying on listening alone.

## Privacy principle

Raw microphone audio is not stored. Live microphone buffers are reduced in memory to measurements such as level, spectrum, noise floor, candidate frequencies, and persistence metrics.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
