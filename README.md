# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#9 — dominant-frequency detection** is implemented.

The Lab now detects and ranks low-frequency spectral peaks from **20–200 Hz**. Detection uses both local spectral prominence and the adaptive temporal noise floor, so a steady road-drone peak can still be recognized even if it was already present when floor tracking began.

Candidates are de-duplicated when they are too close together, ranked by prominence plus floor excess, and refined with parabolic interpolation so their estimated frequency is not limited strictly to the FFT-bin center.

The current detector is intentionally instantaneous. The next milestone adds persistence and confidence over time so QuietDrive can distinguish a repeatable cabin tone from a short transient.

## Privacy principle

Raw microphone audio is not stored. Live microphone buffers are reduced in memory to measurements such as level, spectrum, noise floor, and candidate dominant frequencies.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
