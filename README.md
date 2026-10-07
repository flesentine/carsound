# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#37 — repeatability** is implemented.

QuietDrive now performs matched cross-session repeatability analysis on saved A/B evidence. Comparisons are grouped only when route signature, target frequency, phase, and output level match after small display-level normalization, and multiple trials inside one app session are averaged before any cross-session judgment is made.

## Structured event schema

Every saved event includes:

- schema version
- event UUID
- timestamp
- app-session UUID
- per-session sequence number
- typed event kind
- current route signature/revision
- matching calibration-profile ID when available
- current target frequency, phase, and output level
- current overall-confidence score
- current evidence coverage
- current confidence label
- event-specific numeric metrics
- event-specific text fields
- boolean flags
- reference IDs linking events to durable calibration, route-test, or experiment records

Each app launch starts a new session UUID. Sequence numbers restart at 1 for that session, while older sessions remain available in the same local event history.

The store is capped at **10,000 events**; oldest events are removed first.

## What is logged

Structured logging now covers:

- app/session start
- audio route-test capture
- calibration completion/failure
- saved baseline/treatment comparisons
- automatic phase-sweep completion/failure
- fine phase-refinement completion/failure
- amplitude-search completion/failure
- adaptive accepted adjustments
- adaptive fail-safe/stop outcomes
- Bluetooth jitter completion/failure
- sound-vibration correlation completion/failure
- microphone capture start/stop
- generated-tone start/stop
- emergency **MUTE NOW**
- explicit overall-confidence snapshots

A/B measurement events preserve derived energy, reduction, variability, and sample-count metrics and link back to the existing durable experiment record.

The Cancellation Lab now includes a **Structured Logs** card showing the current session, total event/session counts, recent event names and sequence numbers, persistence errors, a manual **Log Confidence Snapshot** control, and a clear-all action.

## Privacy and storage

Structured logging stores **derived experiment metadata only**.

It does **not** store:

- raw microphone audio
- raw microphone PCM buffers
- raw accelerometer sample streams
- song fingerprints or recognized content

The log is stored locally as atomic JSON under Application Support.

## CSV/JSON export

The Structured Logs card now lets the researcher choose **All saved** or **Current session** and save either format through the native iOS file exporter.

- **JSON** exports the typed `StructuredLogEvent` array with pretty printing, stable key ordering, and ISO-8601 timestamps.
- **CSV** keeps stable event/context columns and adds deterministic columns for every observed numeric metric, text field, boolean flag, and reference ID.
- CSV values use locale-independent numeric formatting and standard quote escaping for commas, quotes, and line breaks.
- Export filenames include the selected scope and a UTC timestamp.
- Exporting does not add raw microphone audio, raw PCM buffers, or raw accelerometer streams; those data were never part of the structured log.

## Test dashboard

The Cancellation Lab now includes a compact **Test Dashboard** card that opens a dedicated dashboard screen.

The dashboard can switch between **All saved** evidence and the **Current session**. It reports:

- total structured events and app sessions
- distinct route signatures and target frequencies
- saved A/B comparison count
- comparisons with positive measured reduction
- average and best measured reduction
- latest confidence score, evidence coverage, and confidence label
- explicit confidence-snapshot count and average snapshot score
- total workflow failures and emergency safety mutes
- completion/failure counts for route tests, calibration, A/B comparisons, phase sweep, fine phase, amplitude search, adaptive control, Bluetooth jitter, and sound/vibration correlation
- up to eight recent session summaries with build tag, timestamp, event/comparison counts, route/frequency coverage, best reduction, latest confidence, failures, and safety mutes

The dashboard is computed from the existing structured log. Opening it does not create new experiment records or duplicate persistence.

## Repeatability

The Test Dashboard now includes a dedicated **Repeatability** view derived from the structured event log.

A saved A/B comparison is eligible only when it has a measured-reduction value plus complete route/frequency/phase/output context. Conditions are matched using:

- exact route signature
- target frequency rounded to the nearest 0.1 Hz
- phase rounded to the nearest 1°
- output level rounded to the nearest 1 percentage point

Repeated trials inside one app session are averaged first. Cross-session assessment therefore uses **session means**, preventing a large automatic search in one session from masquerading as many independent repetitions.

Assessment maturity requires at least **3 separate sessions**. Two sessions are labeled **Early cross-session evidence**. Mature groups use a ±0.5 dB near-zero deadband; tight consistency additionally requires session-mean standard deviation ≤1.0 dB and total session-mean range ≤2.0 dB. Mature outcomes are labeled Consistent reduction, Consistent near-zero result, Consistent worsening, Variable result, or Mixed direction.

The Repeatability view reports matched-condition counts, analyzable/excluded A/B records, cross-session/mature groups, consistent-reduction groups, per-condition mean/spread/direction counts, and each session's mean and trial range.

## Why this matters

#37 prevents repeated search trials from overstating evidence and makes disagreement across days/sessions visible before the final decision:

- **#38 head-position sensitivity** can add physical-position context that repeatability currently cannot control
- **#39 multiple frequencies** can broaden target coverage using the same evidence structure
- **#40 go/no-go report** can combine confidence, repeatability, position sensitivity, and frequency coverage

## Verification status

The app and unit-test targets compile successfully in GitHub Actions using the iOS simulator SDK. CI uses `build-for-testing`, so tests compile but are not executed there.

Structured-log coverage includes schema/version persistence, metrics/text/flags/reference round-trip, session sequencing, cross-launch session separation, retention pruning, and clear/restart behavior.

The unit-test target also covers JSON export round-trip fidelity, deterministic CSV field flattening, CSV quote/comma/newline escaping, current-session filtering, all-events filtering, and timestamped export filenames.

Dashboard analytics coverage verifies aggregate event/session/route/frequency counts, A/B reduction statistics, confidence aggregation, workflow completion/failure accounting, safety-mute accounting, current-session filtering, recent-session ordering, build tags, and session durations.

Repeatability coverage verifies normalized condition grouping, per-session averaging, cross-session maturity, consistent reduction/worsening/near-zero classification, mixed-direction detection, and exclusion of comparisons missing complete match context. GitHub Actions still uses `build-for-testing`, so these tests compile there but are not executed.

## What comes next

**#38 — head-position sensitivity** is next.

The remaining Milestone 4 roadmap is:

- #38 head-position sensitivity
- #39 multiple frequencies
- #40 Lab go/no-go report

## Generate the Xcode project

This repository uses XcodeGen so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See `docs/STATUS.md`.
