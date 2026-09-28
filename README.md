# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#13 — manual output-level control** is implemented.

The tone generator now has a live **0–100% output control** inside a hard digital ceiling. The generated PCM waveform is capped at **0.02 sample amplitude**, about **-33.98 dBFS** at the maximum setting. The default is **50%**, which preserves the previous milestone's effective **0.01 amplitude / about -40 dBFS** level rather than silently making the default louder.

Live output changes use a short **60 ms ramp**. Start and stop retain their **120 ms ramps**. The Lab also has an immediate **MUTE NOW** control that sets player output to zero without waiting for a ramp; Resume returns to the selected level smoothly.

The digital cap is only a signal-level limit. It does **not** guarantee a particular acoustic SPL because the phone route, car amplifier, and stereo volume still determine actual speaker loudness.

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
