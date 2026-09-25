# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#6 — live spectrum graph** is implemented.

The Lab now renders the rolling FFT as a live raw spectrum using a SwiftUI Canvas. The default view focuses on **20–200 Hz**, the range most relevant to persistent road and powertrain drone experiments, with an optional **20–2,000 Hz** context view. The spectrum is deliberately unsmoothed so the next milestone can add and evaluate smoothing separately.

## Privacy principle

Raw microphone audio is not stored. Live microphone buffers are reduced in memory to measurements such as level and frequency-spectrum bins.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
