# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#14 — manual phase control** is implemented.

The generated low-frequency sine can now be shifted manually through **0–360°**, with quick **0° / 90° / 180° / 270°** presets and an **Invert +180°** control. Phase is normalized modulo one complete cycle, and the PCM generator applies that phase without changing the selected frequency or the hard-capped output amplitude.

Phase can also be changed while the tone is playing. To reduce hard discontinuities, live slider changes are briefly debounced, the output ramps down for about **35 ms**, the player swaps to the newly phased loop, and output ramps back to the selected level over another **35 ms**.

A crucial physical limitation remains: this is **generated digital phase**. Bluetooth/car-audio latency and jitter can shift the acoustic phase that ultimately reaches the phone microphone. The later measurement and phase-search milestones are what determine whether a particular generated phase actually reduces the target cabin tone.

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
