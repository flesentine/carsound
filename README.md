# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#11 — low-frequency-only analysis mode** is implemented.

QuietDrive now defaults to **ANC Focus**, which keeps downstream signal analysis inside **30–200 Hz**, the primary band for the upcoming cancellation experiments. A **Wide Lab** mode retains **20–2,000 Hz** context for broader diagnostics.

The 4,096-sample FFT is still computed normally because the transform itself requires the full time-domain window. The mode filter is applied immediately afterward, so smoothing, noise-floor tracking, dominant-frequency detection, persistence tracking, and the raw-spectrum display only consume the selected band.

Mode switching is intentionally disabled while microphone capture is active so state from two different frequency bands cannot be mixed.

This completes **Milestone 1 — Hear the car (#1–#11)**. The next phase begins with **#12 — tone generator**.

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
