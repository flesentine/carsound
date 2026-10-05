# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#32 — overall confidence scoring** is implemented. This completes **Milestone 3 — Reality (#23–#32)**.

QuietDrive now combines the independent evidence streams built across the project into one **explainable confidence score** while keeping the actual measured dB reduction separate.

The score uses seven weighted components:

- **Tone evidence — 18 points**
- **Measurement quality — 16 points**
- **Measured reduction — 14 points**
- **Adaptive stability — 14 points**
- **Route timing — 14 points**
- **Sound/vibration evidence — 12 points**
- **Interference / safety — 12 points**

The component weights total 100, but the UI also reports **evidence coverage** separately. Missing diagnostics do not become fake zero scores; they reduce coverage. QuietDrive requires at least **60% evidence coverage** before it will label the result Low, Moderate, or High confidence.

This design deliberately prevents one impressive-looking measurement from dominating the conclusion. A one-off 6 dB reduction cannot produce High confidence if the target tone is unstable, measurements are noisy, Bluetooth timing is unresolved, the adaptive controller is oscillating, or music is contaminating the microphone.

Hard red flags also cap the final score:

- microphone clipping → maximum 20
- target amplification of 3 dB or more → maximum 20
- adaptive fail-safe → maximum 35
- unstable Bluetooth timing → maximum 55
- likely program-audio interference → maximum 60

The Cancellation Lab now shows the overall score, evidence coverage, confidence level, every weighted component with its detail, and the specific factors limiting the result.

The score is **confidence in the current experimental evidence**. It is not the measured cancellation itself, and it is not a probability that full-car active noise cancellation will work.

## Milestone 3 complete

QuietDrive now includes:

- bounded adaptive phase/amplitude control
- adaptive stability protection
- processing-latency diagnostics
- route-specific testing
- Bluetooth profile characterization
- live Bluetooth timing/jitter diagnostics
- accelerometer capture
- vibration-spectrum analysis
- sound/vibration correlation
- music/program-audio interference detection
- overall evidence confidence scoring

The software is now substantially better at telling us **when a result is trustworthy and when it is not**.

## Verification status

The app and unit-test targets compile successfully in GitHub Actions using the iOS simulator SDK. CI uses `build-for-testing`, so tests compile but are not executed there.

Confidence scoring has deterministic coverage for high-quality evidence, sparse evidence, missing optional diagnostics, clipping, target amplification, adaptive fail-safe, unstable Bluetooth timing, and likely music interference.

Physical vehicle testing is still mandatory. High confidence in one controlled run does not establish repeatability across vehicles, road surfaces, speeds, phone mounting positions, temperatures, routes, head units, or days.

## What comes next

**Milestone 4 — Prove it** starts with **#33 calibration**.

The remaining roadmap is:

- #33 calibration
- #34 structured logs
- #35 CSV/JSON export
- #36 test dashboard
- #37 repeatability
- #38 head-position sensitivity
- #39 multiple frequencies
- #40 Lab go/no-go report

## Privacy principle

Raw microphone audio is not stored. Raw accelerometer samples remain in memory only. Confidence scoring uses only derived diagnostic measurements already produced locally by the Lab.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
