# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#5 — FFT processing** is implemented.

The app now accumulates the live 1,024-frame microphone callbacks into a rolling 4,096-sample analysis window, applies a Hann window, performs a radix-2 FFT, and produces a full frequency spectrum in dBFS from DC to Nyquist. At a 48 kHz microphone rate the current spectral resolution is about 11.72 Hz per bin.

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
