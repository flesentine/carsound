# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#7 — spectrum smoothing** is implemented.

The live spectrum can now switch between the untouched raw FFT and temporal smoothing. Smoothing is performed in linear power rather than by directly averaging dB values, with **Responsive**, **Balanced**, and **Stable** presets. The default Balanced view is intended to make persistent cabin-noise structure easier to see without hiding the raw measurements.

To keep the audio callback efficient, smoothing is restricted to the 0–2,000 Hz analysis band used by the Lab graphs.

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
