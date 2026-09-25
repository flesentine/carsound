# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#10 — persistent-tone detection** is implemented.

QuietDrive now tracks dominant 20–200 Hz candidates across the captured-audio timeline instead of treating each FFT frame independently. A candidate is matched across frames by frequency, allowed brief dropouts, and evaluated for duration, presence rate, frequency stability, local spectral prominence, and temporal floor excess.

By default, a tone must survive for at least **2 seconds**, appear often enough, and remain frequency-stable before the Lab marks it **Persistent**. The UI also reports a Low / Medium / High confidence score and the underlying measurements used to derive it.

This completes items #1–#10 of the original development roadmap. Item #11 is the dedicated low-frequency-only analysis mode before the tone-generation/cancellation work begins.

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
