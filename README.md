# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#34 — structured logs** is implemented.

QuietDrive now has a common, durable event stream for the remaining **Milestone 4 — Prove it** work. Instead of each experiment feature keeping isolated UI state, important actions and outcomes can now be analyzed as one ordered machine-readable history.

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

## Why this matters

#34 is the data foundation for the next work:

- **#35 CSV/JSON export** can serialize one consistent event schema
- **#36 test dashboard** can aggregate sessions and workflows
- **#37 repeatability** can compare matched runs across sessions/conditions
- **#40 go/no-go report** can use a traceable evidence history instead of manually reconstructed results

## Verification status

The app and unit-test targets compile successfully in GitHub Actions using the iOS simulator SDK. CI uses `build-for-testing`, so tests compile but are not executed there.

Structured-log coverage includes schema/version persistence, metrics/text/flags/reference round-trip, session sequencing, cross-launch session separation, retention pruning, and clear/restart behavior.

## What comes next

**#35 — CSV/JSON export** is next.

The remaining Milestone 4 roadmap is:

- #35 CSV/JSON export
- #36 test dashboard
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
