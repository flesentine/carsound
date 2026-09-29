# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#19 — automatic phase sweep** is implemented.

After a baseline has been captured, the Cancellation Lab can now automatically test a coarse phase grid:

**0° → 45° → 90° → 135° → 180° → 225° → 270° → 315°**

The target frequency and output level remain fixed. For every phase, QuietDrive waits for the generator/acoustic path to settle, collects the same 20-sample target-energy treatment window used by the A/B measurement system, compares it against the same baseline, and saves the result to the durable experiment history.

The live sweep table reports each phase's treatment-band energy and its change relative to baseline. The best coarse candidate is selected by the **lowest measured treatment-band energy**, with lower variability used as the tie-breaker when two results are effectively equal.

The generator is automatically muted when the sweep finishes. The user can then apply the best coarse phase explicitly. Cancel Sweep, MUTE NOW, and Stop All all safely terminate an active sweep.

This is deliberately only a **coarse 45° search**. **#20 — refine phase search** will search more tightly around the best coarse region instead of treating the winning 45° point as the final optimum.

## Privacy principle

Raw microphone audio is not stored. Live microphone buffers are reduced in memory to measurements such as level, spectrum, noise floor, candidate frequencies, persistence metrics, target-band energy, comparison summaries, phase-sweep results, and saved experiment metadata.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
