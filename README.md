# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#3 — microphone capture** is implemented.

The app now configures an `AVAudioSession` for simultaneous playback and recording, exposes the active audio route, and uses `AVAudioEngine` to stream live PCM microphone buffers in memory. Capture metadata is counted and displayed without writing raw audio to disk.

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
