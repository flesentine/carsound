# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#22 — adaptive controller** is implemented. This completes **Milestone 2 — Fight one frequency (#12–#22)**.

The controller starts from the best phase/output found by the coarse phase sweep, fine phase refinement, and amplitude search. It then performs a deliberately bounded local search rather than making large uncontrolled changes.

The loop alternates:

- **phase probes:** current accepted phase ±5°
- **output probes:** current accepted output ±2%

Each setting is measured with a 10-sample target-energy window. A candidate must improve target-band energy by at least **0.35 dB** before QuietDrive accepts it. Otherwise the controller restores the previous accepted settings.

Adaptive output remains bounded by the user's amplitude-search ceiling, the 2% automatic-control minimum, and the app's existing hard PCM ceiling.

The controller includes conservative fail-safe behavior. Generated output is immediately muted if the measurement path disappears, the input/output route changes, the audio session or microphone capture stops, ANC Focus is lost, the target frequency changes, measurements remain unstable, or the active treatment measures **3 dB or more above the no-tone baseline**.

Accepted adaptive adjustments are stored in the durable experiment history. The Cancellation Lab shows the active accepted phase/output, latest target energy and reduction, measurement variability, iterations, accepted adjustments, rollbacks, and the controller's latest action.

This remains an **experimental lab controller**. Simulator CI can prove the code and test target compile, but it cannot prove acoustic cancellation, Bluetooth timing stability, safe speaker output, or sustained feedback stability in a real vehicle.

## What comes next

**Milestone 3 — Reality** starts with #23 stability protection, then latency measurement, audio-route testing, Bluetooth characterization/jitter diagnostics, vibration sensing, sound/vibration correlation, music-interference detection, and overall confidence scoring.

## Privacy principle

Raw microphone audio is not stored. Live microphone buffers are reduced in memory to measurements such as level, spectrum, noise floor, candidate frequencies, persistence metrics, target-band energy, comparison summaries, search/controller results, and saved experiment metadata.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
