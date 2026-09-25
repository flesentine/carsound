# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#4 — raw audio diagnostics** is implemented.

The app now streams live PCM microphone buffers in memory and reports RMS level, peak level, peak hold, digital headroom, clipping, buffer size/duration, sample rate, channel count, and PCM format. Signal levels are reported in dBFS; they are not presented as calibrated cabin SPL.

## Privacy principle

Raw microphone audio is not intended to be stored. Analysis stages reduce live microphone buffers to measurements such as level, spectrum, frequency peaks, and confidence values.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
