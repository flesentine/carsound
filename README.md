# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#31 — music interference detection** is implemented.

QuietDrive now automatically scores whether the live microphone spectrum looks contaminated by **broad, changing program audio** rather than only by narrow cabin/engine tones.

The detector operates on the raw full microphone FFT even when the Lab is using ANC Focus for the main cancellation workflow. It compares:

- low-frequency energy from **30–200 Hz**
- program-band energy from **200–4000 Hz**
- broadband spectral occupancy
- spectral flatness
- frame-to-frame spectral change
- program-band strength relative to the low-frequency band

Those features are combined into an instantaneous score and then temporally smoothed into one of three states:

- **Clear**
- **Possible interference**
- **Likely interference**

The classifier deliberately includes two false-positive guards. A strong **single sine/test tone** is capped below the Possible threshold, so QuietDrive's own generated cancellation tone is not treated as music. Broad but nearly static road/wind-like spectra can reach Possible, but cannot reach Likely unless the spectrum also changes measurably over time.

The Cancellation Lab now shows the current interference level plus the component metrics behind it.

This is a **spectral interference detector**, not a content-recognition system. It cannot identify a song, artist, or source, and speech or other changing broadband sounds can also register as interference. The point is to know when microphone evidence is contaminated enough that downstream confidence should be reduced.

## Verification status

The app and unit-test targets compile successfully in GitHub Actions using the iOS simulator SDK. CI uses `build-for-testing`, so the tests compile but are not executed there.

Synthetic coverage includes low-frequency road-like spectra, a strong narrow program-band tone, static broadband spectra, changing broadband program-audio-like spectra, and spectral-flux behavior.

Real-world thresholds still need physical driving tests with music off/on at different cabin volumes.

## What comes next

**#32 — overall confidence scoring** is next and is the final Milestone 3 item. It will combine tone persistence, cancellation measurement quality, route/Bluetooth timing stability, sound-vibration correlation, clipping/stability state, and the new music-interference signal into one evidence-based confidence score.

## Privacy principle

Raw microphone audio is not stored. Music interference detection uses only derived FFT magnitudes and keeps no song/content fingerprint.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
