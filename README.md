# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#12 — tone generator** is implemented.

The Lab can now generate a continuous **20–200 Hz sine wave** through an `AVAudioPlayerNode`. Frequencies are integer-Hz values so the one-second PCM buffer contains an integer number of cycles and loops without a phase discontinuity at the buffer boundary.

For this milestone, output is intentionally fixed at a conservative **0.01 sample amplitude (about -40 dBFS)**. Start and stop use a **120 ms volume ramp** to reduce clicks and abrupt low-frequency transients. Manual output-level control is deliberately deferred to **#13**.

The generator follows the active output-route sample rate and can run alongside the existing play-and-record session. Physical iPhone/car testing is still required before treating simultaneous microphone capture and generated car-speaker output as verified behavior.

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
