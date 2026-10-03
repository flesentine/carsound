# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#29 — vibration spectrum analysis** is implemented.

QuietDrive now converts the rolling accelerometer buffer into a live structural-vibration spectrum.

The motion capture requests **200 Hz** for spectrum work, but the analyzer never assumes the phone actually delivers that rate. It measures the real Core Motion timestamps and derives the observed sample rate from them. The displayed frequency band is limited to **90% of observed Nyquist**, capped at 100 Hz.

That distinction matters. If a phone only delivers around 100 Hz, QuietDrive will stop the trustworthy vibration spectrum near 45 Hz and explicitly report that a 72 Hz vibration cannot be resolved. It will not alias a higher-frequency vibration into a fake lower-frequency peak. Apple documents the maximum Core Motion update rate as hardware-dependent, so physical-device behavior is intentionally measured rather than assumed.

Before FFT analysis, the latest motion samples are resampled onto a uniform time grid and each accelerometer axis is high-pass filtered at **1.5 Hz** to suppress gravity and slow phone tilt. X, Y and Z are FFT analyzed independently, then their amplitudes are combined into a vector vibration spectrum so dominant frequencies are less dependent on how the phone is oriented.

The live Vibration Spectrum panel reports:

- observed accelerometer sample rate
- Nyquist frequency
- trustworthy analyzed frequency band
- FFT frequency resolution
- high-pass cutoff
- dynamic vibration RMS
- dominant vibration peaks and amplitudes in milli-g
- whether the current sample rate can directly resolve 72 Hz

A live spectrum graph is also shown while enough accelerometer samples are available.

## Verification status

The app and unit-test targets compile successfully in GitHub Actions using the iOS simulator SDK. CI uses `build-for-testing`, so the tests compile but are not executed there.

Synthetic test coverage includes known 20 Hz and 72 Hz vibration signals, Nyquist rejection when sampling is too slow, gravity/DC rejection, and timestamp resampling.

Meaningful vibration measurements still require a physical iPhone mounted consistently in the vehicle. Spectrum amplitudes are relative device acceleration, not calibrated chassis displacement, force, or road-input measurements.

## What comes next

**#30 — correlate vibration and sound** is next. QuietDrive now has independent acoustic and vibration frequency measurements, so the next step is to determine when a microphone tone and structural vibration occupy the same frequency region and how strongly they move together.

## Privacy principle

Raw microphone audio is not stored. Raw accelerometer samples remain only in the in-memory rolling buffer for local vibration analysis and are not uploaded.

## Generate the Xcode project

This repository uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See [`docs/STATUS.md`](docs/STATUS.md).
