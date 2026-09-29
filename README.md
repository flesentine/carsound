# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#20 — refined phase search** is implemented.

After the coarse 45° sweep from #19 identifies a promising region, QuietDrive can now run a **two-stage fine phase search** around that result.

**Stage 1** tests the coarse winner **±30° at 15° spacing**.

**Stage 2** takes the best Stage-1 result and tests **±10° at 5° spacing**.

The phase grid wraps correctly across 0°/360°, and both stages reuse the same baseline, target frequency, output level, settling delay, target-energy measurement, and treatment-window averaging used by the existing experiment system.

Every fine-search measurement is automatically saved to durable experiment history. The Cancellation Lab shows Stage 1 and Stage 2 result tables separately, identifies the best result from each stage, and then reports the **best refined phase across both stages**. The user can explicitly apply that refined phase after the search.

Generated output is automatically muted when refinement completes. Cancel Fine Search, MUTE NOW, and Stop All all safely terminate active refinement.

The refined result is now resolved to a **5° digital-phase grid**. It is still an experimentally measured digital setting rather than a direct measurement of physical acoustic phase.

With phase search now coarse-to-fine, **#21 — automatic amplitude search** can hold the refined phase fixed and search for the output level that produces the lowest target-band energy without exceeding the existing digital safety ceiling.

## Privacy principle

Raw microphone audio is not stored. Live microphone buffers are reduced in memory to measurements such as level, spectrum, noise floor, candidate frequencies, persistence metrics, target-band energy, comparison summaries, phase-search results, and saved experiment metadata.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
