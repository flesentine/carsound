# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#18 — experiment recorder** is implemented.

Completed before/after comparisons can now be saved as durable experiment runs instead of disappearing when the comparison is reset. The recorder writes local JSON under the app's Application Support directory and reloads the history automatically on launch.

Each saved run includes:

- timestamp
- target frequency
- treatment phase
- treatment output level
- baseline and treatment target-band energy
- treatment-minus-baseline dB
- measured reduction dB
- center-frequency levels
- baseline and treatment variability
- sample counts and measurement-window durations
- input route
- output route

The Cancellation Lab shows a newest-first experiment history with per-run delete and clear-all controls. The screen displays the 20 most recent runs while the local recorder retains the full history.

Only measurement summaries and settings are stored. **Raw microphone audio is never written to the experiment recorder.**

With durable trial history in place, **#19 — automatic phase sweep** can systematically test multiple phase values and compare them rather than relying on manual one-off trials.

## Privacy principle

Raw microphone audio is not stored. Live microphone buffers are reduced in memory to measurements such as level, spectrum, noise floor, candidate frequencies, persistence metrics, target-band energy, comparison summaries, and saved experiment metadata.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
