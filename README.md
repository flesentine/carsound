# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#2 — audio-session routing** is implemented.

The app now configures an `AVAudioSession` for simultaneous playback and recording using measurement mode, supports Bluetooth A2DP output, displays the actual current input/output routes, and reacts to route changes.

## Privacy principle

Raw microphone audio is not intended to be stored. Later analysis stages will reduce microphone buffers to measurements such as level, spectrum, frequency peaks, and confidence values.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
