# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#36 — test dashboard** is implemented.

QuietDrive now turns its durable structured-event history into an in-app evidence dashboard. The dashboard summarizes saved sessions, routes, target frequencies, A/B measurement outcomes, confidence evidence, workflow completions/failures, safety mutes, and recent-session details without inventing a premature pass/fail score.

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

## Why this matters

#36 makes the accumulated evidence visible enough to guide the remaining proof work without pretending that one strong result proves ANC effectiveness:

- **#37 repeatability** can reuse the same pure analytics layer to compare matched runs across sessions and conditions
- **#38 head-position sensitivity** can add positional evidence to the same session history
- **#39 multiple frequencies** can broaden target coverage
- **#40 go/no-go report** can use a traceable evidence history instead of manually reconstructed results

## Verification status

The app and unit-test targets compile successfully in GitHub Actions using the iOS simulator SDK. CI uses `build-for-testing`, so tests compile but are not executed there.

Structured-log coverage includes schema/version persistence, metrics/text/flags/reference round-trip, session sequencing, cross-launch session separation, retention pruning, and clear/restart behavior.

The unit-test target also covers JSON export round-trip fidelity, deterministic CSV field flattening, CSV quote/comma/newline escaping, current-session filtering, all-events filtering, and timestamped export filenames.

Dashboard analytics coverage verifies aggregate event/session/route/frequency counts, A/B reduction statistics, confidence aggregation, workflow completion/failure accounting, safety-mute accounting, current-session filtering, recent-session ordering, build tags, and session durations. GitHub Actions still uses `build-for-testing`, so these tests compile there but are not executed.

## What comes next

**#37 — repeatability** is next.

The remaining Milestone 4 roadmap is:

- #37 repeatability
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
