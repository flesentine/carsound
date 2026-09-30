# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#28 — accelerometer capture** is implemented.

QuietDrive can now capture raw iPhone accelerometer data alongside the existing microphone/audio diagnostics.

The motion path requests **100 Hz** accelerometer delivery and records each Core Motion sample with a monotonic sensor timestamp plus X/Y/Z acceleration in g. Because the requested Core Motion interval is not a guarantee of exact delivery cadence, the app also measures the observed rate, average sample interval, timing jitter, and minimum/maximum interval.

A dedicated thread-safe store receives Core Motion callbacks off the SwiftUI main actor. The newest **4,096 samples** are retained in an in-memory ring buffer—roughly 41 seconds at 100 Hz—so #29 can analyze vibration without adding disk writes to the sensor callback.

The Cancellation Lab now shows:

- accelerometer availability/capture state
- live X/Y/Z acceleration
- acceleration magnitude
- requested sample rate
- observed sample rate
- average sample interval
- interval jitter
- minimum/maximum interval
- total samples captured
- samples currently retained
- elapsed capture duration

Raw accelerometer values include gravity and depend on phone orientation. QuietDrive does not yet interpret the raw magnitude as vehicle vibration strength. **#29 — vibration-spectrum analysis** will remove the static/slow component and analyze vibration energy in the frequency domain.

Motion samples remain local and in memory only. They are not uploaded or added to experiment-history JSON.

## Verification status

The app and unit-test targets compile successfully in GitHub Actions using the iOS simulator SDK. CI uses `build-for-testing`, so tests compile but are not executed there.

The simulator can verify the code path but cannot supply meaningful vehicle accelerometer data. Physical iPhone testing is required for vibration measurements.

## What comes next

**#29 — vibration-spectrum analysis** is next. It will turn the rolling accelerometer buffer into a low-frequency vibration spectrum so QuietDrive can identify persistent structural frequencies and then compare them with cabin sound in #30.

## Privacy principle

Raw microphone audio is not stored. Raw accelerometer samples are retained only in the in-memory rolling buffer for local analysis and are not uploaded.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
