# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#26 — Bluetooth behavior characterization** is implemented.

QuietDrive no longer treats Bluetooth as one generic route. The active Bluetooth path is classified as:

- A2DP
- HFP
- Bluetooth LE
- Mixed Bluetooth
- No Bluetooth

The app also identifies the observed topology:

- Bluetooth output + local/non-Bluetooth input
- Bluetooth input + output
- Bluetooth input only
- mixed Bluetooth path
- no Bluetooth path

This matters because two experiments can both look like “Bluetooth” to a user while actually using very different input/output arrangements.

The Bluetooth Behavior panel combines the **current route** with the durable route-test history from #25. It reports current sample rate, I/O buffer, iOS input/output latency, route revision, saved Bluetooth test count, distinct Bluetooth routes, profiles seen so far, and observed profile switches.

For each Bluetooth profile with saved physical captures, QuietDrive calculates observed averages for:

- sample rate
- I/O buffer duration
- input latency
- output latency
- callback jitter
- estimated spectrum-center age

If non-Bluetooth route tests have also been saved, the current Bluetooth output latency is compared against that non-Bluetooth average so the route difference is visible as measured data rather than an assumption.

## Verification status

The app and unit-test targets compile successfully in GitHub Actions using the iOS simulator SDK. CI uses `build-for-testing`, so tests compile but are not executed there.

The Bluetooth characterization logic can be verified in CI, but useful profile statistics require repeated captures on a physical iPhone using the actual car/head-unit connection.

This milestone remains observational. It does not declare A2DP, HFP, or LE suitable or unsuitable for cancellation from theory alone.

## What comes next

**#27 — Bluetooth jitter diagnostics** is next. Instead of comparing static route snapshots, QuietDrive will track Bluetooth timing variation over repeated live samples so we can see whether latency/cadence is stable enough for phase-sensitive cancellation.

## Privacy principle

Raw microphone audio is not stored. Bluetooth characterization uses route metadata and timing summaries already captured by the route-testing system.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
