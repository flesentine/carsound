# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#23 — stability protection** is implemented.

The adaptive controller from #22 is now wrapped in a conservative stability layer designed to prevent it from chasing measurement noise or drifting far away from the phase/output settings established by the controlled search pipeline.

The controller is confined to a **trusted envelope** around its optimized starting point:

- phase: no more than **±20°**
- output: no more than **±8 percentage points**
- output also remains below the user-selected amplitude-search ceiling and the existing hard PCM ceiling

The phase limit uses circular distance, so a seed near 360° behaves correctly across the 0° boundary.

After an adaptive adjustment is accepted, QuietDrive forces a full monitoring iteration before probing again. If four probe cycles in a row are rejected, the controller enters a three-iteration **stability hold** rather than continuously hunting around a stable optimum.

QuietDrive also watches for accepted-control oscillation. If phase or amplitude repeatedly reverses direction three accepted times in succession, the controller treats that behavior as instability and triggers the existing fail-safe mute path.

Adaptive measurement windows now accept only **fresh FFT transforms**. The controller tracks the FFT transform sequence and will not count the same published spectrum snapshot multiple times as independent samples. If fresh measurements stop arriving, the bounded collection window eventually triggers the existing missing-measurement fail-safe.

Microphone clipping is now an explicit adaptive fail-safe as well.

The Cancellation Lab reports phase/output drift from the seed, stability-hold count, remaining hold iterations, and phase/amplitude reversal streaks.

## Verification status

The app and unit-test targets compile successfully in GitHub Actions using the iOS simulator SDK. CI uses `build-for-testing`, so the tests compile but are not executed there.

These protections reduce software-side instability risk, but they do **not** prove physical acoustic-loop stability. Real iPhone/car testing is still required, particularly for route latency, Bluetooth jitter, amplifier/speaker behavior, and physical feedback.

## What comes next

**#24 — processing latency** is next in Milestone 3. After that come audio-route testing, Bluetooth characterization and jitter diagnostics, vibration sensing, sound/vibration correlation, music-interference detection, and overall confidence scoring.

## Privacy principle

Raw microphone audio is not stored. Live microphone buffers are reduced in memory to measurements such as level, spectrum, noise floor, candidate frequencies, persistence metrics, target-band energy, comparison summaries, search/controller results, stability diagnostics, and saved experiment metadata.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
