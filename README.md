# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#21 — automatic amplitude search** is implemented.

After coarse and fine phase search identify a refined phase, QuietDrive can now hold that phase fixed and automatically search output amplitude.

The user's **currently selected output level becomes the search ceiling**. QuietDrive may test lower output levels, but it will not silently test above that selected level. The existing hard PCM ceiling remains underneath this additional user-controlled ceiling.

The amplitude search runs in two stages:

- **Stage 1:** coarse 10% output steps up to the selected ceiling.
- **Stage 2:** ±10% around the coarse winner using 2% steps, clamped to the same ceiling.

A non-round ceiling is included exactly. For example, a 42% ceiling produces a coarse grid of **10%, 20%, 30%, 40%, 42%**.

Every level uses the same baseline, target frequency, refined phase, settling interval, 20-sample treatment window, and linear-power comparison math used elsewhere in the Cancellation Lab. Every result is automatically saved to durable experiment history.

The winning output is the level with the **lowest measured treatment-band energy**. If energies are effectively equal, QuietDrive prefers lower variability; if those are also equal, it prefers the **lower output level**.

The generator is automatically muted when the search completes. Cancel Amplitude Search, MUTE NOW, and Stop All safely terminate an active search.

With target detection, measurement, A/B comparison, durable experiments, coarse/fine phase search, and amplitude search now in place, **#22 — adaptive controller** is the remaining Milestone 2 item.

## Privacy principle

Raw microphone audio is not stored. Live microphone buffers are reduced in memory to measurements such as level, spectrum, noise floor, candidate frequencies, persistence metrics, target-band energy, comparison summaries, phase/amplitude search results, and saved experiment metadata.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
