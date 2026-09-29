# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#17 — before/after measurement** is implemented.

The Cancellation Lab can now run a controlled two-window A/B comparison instead of forcing the experimenter to watch a moving live number.

**Baseline** captures about two seconds of target-band energy with the generated tone muted/off. **Treatment** captures the same kind of window with the generated tone actively audible. Each window collects 20 valid readings at 10 Hz after a short settling delay, then averages them in **linear power** before converting back to dB.

The result reports both:

- **treatment − baseline dB**
- **measured reduction dB**

A positive measured reduction means the treatment window contained less target-band energy than the baseline window.

The UI also preserves the target, phase, output level, sample count, duration, and window variability so a comparison is not just a naked number. If the target frequency changes between baseline and treatment, the comparison is rejected and a new baseline is required.

This is still a single in-memory comparison. **#18 — experiment recorder** will preserve runs/history so multiple phase and amplitude trials can be compared systematically.

## Privacy principle

Raw microphone audio is not stored. Live microphone buffers are reduced in memory to measurements such as level, spectrum, noise floor, candidate frequencies, persistence metrics, target-band energy, and comparison summaries.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
