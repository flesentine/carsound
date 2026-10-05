# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#30 — sound/vibration correlation** is implemented.

QuietDrive can now run a controlled **30-second paired correlation window** using the independent microphone and vibration pipelines built in earlier milestones.

Every 0.5 seconds, the correlation model waits for both a fresh microphone FFT and fresh accelerometer data. The current microphone dominant-frequency candidates are then paired one-to-one with vibration peaks using a tolerance derived from the actual audio and vibration frequency resolutions.

The matcher is also constrained by the vibration analyzer's Nyquist-safe upper limit. A microphone tone above the vibration system's trustworthy band is left unresolved rather than matched to an aliased lower-frequency motion peak.

For each matched band QuietDrive tracks:

- sound frequency
- vibration frequency
- frequency difference
- resolution-aware match tolerance
- normalized frequency agreement
- sound level
- vibration amplitude
- whether the sound tone is persistent
- sound persistence confidence

Repeated matches are clustered by shared frequency before any temporal amplitude correlation is calculated. That prevents unrelated bands—such as a 40 Hz structural mode and a 72 Hz mode—from being combined into one meaningless statistic.

The primary shared-frequency track reports:

- how often it appears across paired observations
- mean shared frequency
- average sound/vibration frequency delta
- average frequency agreement
- persistent-sound match ratio
- average persistence confidence
- **Pearson amplitude correlation (r)** between sound strength and vibration amplitude

The live assessment is intentionally descriptive:

- **Insufficient data**
- **No consistent shared frequency**
- **Frequency aligned**
- **Frequency aligned + co-moving**

A positive amplitude correlation means sound and vibration strength tended to rise and fall together on the same frequency track. It does **not** prove that structural vibration caused the sound.

## Verification status

The app and unit-test targets compile successfully in GitHub Actions using the iOS simulator SDK. CI uses `build-for-testing`, so the tests compile but are not executed there.

The correlation math has deterministic synthetic coverage for frequency matching, Nyquist-safe rejection, positive and negative Pearson correlation, repeated shared-frequency tracking, and separation of distinct frequency bands.

Meaningful correlation results still require a physical iPhone in a consistently mounted vehicle position with both microphone and accelerometer capture active.

## What comes next

**#31 — music interference detection** is next. QuietDrive now knows when sound and vibration share a structural-looking frequency; the next step is to recognize when cabin music or other playback is contaminating the microphone spectrum so those observations can be discounted.

## Privacy principle

Raw microphone audio is not stored. Raw accelerometer samples remain in memory only. The correlation layer keeps derived frequency/amplitude observations in memory for the active correlation run and does not upload them.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
