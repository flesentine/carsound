# QuietDrive Lab

QuietDrive Lab is a native iOS research app for testing whether a phone can detect and eventually reduce persistent low-frequency cabin noise using the vehicle audio system.

## Current milestone

Development effort **#40 — final Lab go/no-go report** is implemented.

QuietDrive now combines evidence volume, confidence, cross-session repeatability, head-position robustness, and multi-frequency breadth into a deterministic final Lab verdict: GO, HOLD, or NO-GO.

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
- manual head-position label on saved A/B comparisons
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
- saved baseline/treatment comparisons, including the selected head-position label
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

A saved A/B comparison is eligible only when it has a measured-reduction value plus complete route/frequency/phase/output context. Position-labeled runs are now kept separate in repeatability, so Reference/Left/Right/Forward/Back data cannot be blended into one repeatability condition. Conditions are matched using:

- exact route signature
- target frequency rounded to the nearest 0.1 Hz
- phase rounded to the nearest 1°
- output level rounded to the nearest 1 percentage point

Repeated trials inside one app session are averaged first. Cross-session assessment therefore uses **session means**, preventing a large automatic search in one session from masquerading as many independent repetitions.

Assessment maturity requires at least **3 separate sessions**. Two sessions are labeled **Early cross-session evidence**. Mature groups use a ±0.5 dB near-zero deadband; tight consistency additionally requires session-mean standard deviation ≤1.0 dB and total session-mean range ≤2.0 dB. Mature outcomes are labeled Consistent reduction, Consistent near-zero result, Consistent worsening, Variable result, or Mixed direction.

The Repeatability view reports matched-condition counts, analyzable/excluded A/B records, cross-session/mature groups, consistent-reduction groups, per-condition mean/spread/direction counts, and each session's mean and trial range.

## Head-position sensitivity

Cancellation Lab now includes a **Head Position** selector with five manual posture labels: Reference, Left, Right, Forward, and Back. Selecting a new label after baseline capture invalidates that baseline for treatment/search purposes; a fresh baseline must be captured at the new position.

Each saved A/B event stores `head_position` and a human-readable position title. Historical comparisons without a position label remain valid for earlier analyses but are excluded from head-position sensitivity.

The dedicated **Head-Position Sensitivity** view groups comparisons only when route, target frequency, phase, and output match. Within each position, trials are averaged per session first and then balanced across sessions, preventing one position with many automatic-search trials from dominating the result.

Sensitivity classifications use the spread between position means:
- **Low sensitivity:** spread ≤1.0 dB
- **Moderate sensitivity:** spread >1.0 dB and ≤3.0 dB
- **High sensitivity:** spread >3.0 dB
- **Direction reversal:** at least one position shows reduction >0.5 dB while another shows worsening below −0.5 dB

The view reports tagged/excluded A/B records, matched settings tested at 2+ positions, maximum spread, direction reversals, best/worst position, and session-balanced per-position means.

## Multi-frequency coverage

Cancellation Lab now includes a **Coverage Preset** menu with 40, 60, 80, 100, 120, 160, and 200 Hz targets. These are convenience targets only; detected persistent cabin tones remain more important than filling every preset.

The dedicated **Frequency Coverage** view analyzes saved `comparison_saved` events from 30–200 Hz. Coverage series are separated by exact route signature and head-position label. Phase and output are intentionally allowed to vary by frequency because an effective setting at one wavelength is not expected to transfer unchanged to another.

Target frequencies are rounded to the nearest 1 Hz for coverage grouping. Within each frequency, QuietDrive first finds the best observed reduction in each app session, then averages those per-session best values so a session that generated many search trials cannot dominate the frequency summary. The view also shows the session-balanced all-trial mean and absolute best observed result so search failures are not hidden.

Coverage bands are:
- **Low:** 30–69 Hz
- **Mid:** 70–119 Hz
- **High:** 120–200 Hz

Coverage assessments are:
- **Single target:** only one tested frequency
- **Narrow coverage:** multiple frequencies, all in one band
- **Partial coverage:** frequencies span two bands
- **Broad coverage:** at least three frequencies spanning all three bands

The view reports analyzable/excluded comparisons, distinct targets, multi-target series, broad-coverage series, maximum frequency span, positive-best targets, cross-session targets, per-frequency session counts, comparison counts, and best/average reduction evidence.

## Final Lab go/no-go report

The Test Dashboard now includes a **Final Lab Decision** card and a dedicated **Lab Go / No-Go** report.

The report evaluates five explicit gates:

1. **Evidence volume** — at least 10 saved A/B comparisons across at least 3 sessions that actually contain A/B measurements; launch-only sessions do not count.
2. **Overall confidence** — an explicit Confidence Snapshot must meet the existing 60% assessment floor and 55% Moderate threshold. Once a coherent candidate route exists, the snapshot must come from that same route.
3. **Cross-session repeatability** — at least one mature 3+ session condition must qualify as Consistent reduction. Mature evidence with zero consistent-reduction groups is a blocker.
4. **Head-position robustness** — at least one matched multi-position condition is required. Any direction reversal is a blocker; >3 dB high sensitivity without reversal is a warning.
5. **Frequency breadth** — at least one labeled broad low/mid/high route/head-position series must repeat positive best-per-session evidence at two or more frequencies across separate sessions, and that route/head-position must also have mature repeatable reduction plus safe multi-position evidence.

Verdict logic is intentionally conservative:
- **GO** — every gate passes.
- **HOLD** — there is no blocker, but at least one gate still needs evidence or carries a warning.
- **NO-GO** — one or more mature evidence gates are blockers for the generalized cancellation approach.

The report also exposes the underlying evidence counts and gate summaries rather than returning a verdict without explanation. A plain-text version can be shared through the native iOS share sheet.

A GO verdict means only that the saved Lab evidence justifies continued prototype engineering. It does **not** mean production-ready ANC, safe unattended operation, regulatory compliance, or reliable performance across unmeasured vehicles, road conditions, phone placements, or occupants.

## Why this matters

#40 closes the Lab roadmap with a repeatable decision rule instead of relying on the best-looking individual experiment.

## Verification status

GitHub Actions first compiles the app and unit-test targets with `build-for-testing`, then selects an available iPhone simulator and executes the XCTest suite with `xcodebuild test`. A behavioral test failure now fails CI instead of being hidden by compile-only verification.

Structured-log coverage includes schema/version persistence, metrics/text/flags/reference round-trip, session sequencing, cross-launch session separation, retention pruning, and clear/restart behavior.

The unit-test target also covers JSON export round-trip fidelity, deterministic CSV field flattening, CSV quote/comma/newline escaping, current-session filtering, all-events filtering, and timestamped export filenames.

Dashboard analytics coverage verifies aggregate event/session/route/frequency counts, A/B reduction statistics, confidence aggregation, workflow completion/failure accounting, safety-mute accounting, current-session filtering, recent-session ordering, build tags, and session durations.

Repeatability coverage verifies normalized condition grouping, per-session averaging, cross-session maturity, consistent reduction/worsening/near-zero classification, mixed-direction detection, position separation, and exclusion of comparisons missing complete match context.

Head-position coverage verifies session-balanced position means, sensitivity spread classification, direction reversal detection, exclusion of unlabeled/incomplete comparisons, and protection against mixing labeled positions in repeatability.

Frequency-coverage tests verify route/head-position series separation, 1 Hz target normalization, session-balanced best-result aggregation, repeated-positive cross-session support, low/mid/high band coverage, single/narrow/partial/broad classification, maximum span, and exclusion of incomplete/out-of-band comparisons.

Final-decision coverage verifies the all-gates-pass GO path, comparison-bearing session requirements, unrelated-route evidence rejection, explicit route-coherent confidence snapshots, incomplete-evidence HOLD behavior, head-position direction-reversal NO-GO, adequate-coverage/low-confidence NO-GO, and high-position-sensitivity HOLD behavior.

Post-roadmap review also covers explicit memory-only structured-log storage and the 200 Hz boundary between ANC/road-noise and program-audio interference analysis.

## Post-roadmap hardening

Lab build **4.1** adds a second stability/safety review on top of the #40 decision milestone:

- A/B baselines are bound to the active route signature and route/configuration revision; treatment, automatic searches, and Save Run are blocked after a route/configuration change.
- Route revision now changes when the route identity, sample rate, or I/O buffer duration changes.
- App backgrounding, audio interruptions, and media-services resets stop generated output, microphone capture, active experiment/search workflows, calibration, motion capture, and long-running diagnostics as appropriate.
- Leaving Cancellation Lab cancels active experiment workflows and mutes generated output.
- Resume-from-mute rebuilds the tone buffer from the authoritative current phase before ramping sound back up, preventing UI phase from diverging from the rendered waveform.
- Measurement windows skip microphone-clipped frames and frames marked as likely program-audio interference.
- Repeatability, head-position sensitivity, frequency coverage, and the final decision exclude saved comparisons explicitly flagged as clipped or likely program-contaminated.
- The final evidence-volume gate counts only eligible comparisons.
- Structured-log writes are serialized off the main actor; backgrounding explicitly flushes the latest snapshot.
- GitHub Actions cancels obsolete same-branch runs after newer pushes, while still executing the full XCTest suite on the latest head.

A remaining architectural performance concern is that FFT/spectrum/dominant-tone/music analysis is still performed synchronously from the microphone tap path. A future audio-engine refactor should move non-real-time analysis behind a preallocated queue/ring buffer so DSP cannot perturb audio callback timing.

## Roadmap status

**Milestone 4 is complete through #40.**

The current Lab now covers calibration, structured evidence logging/export, dashboarding, repeatability, head-position sensitivity, multi-frequency coverage, and a final evidence-based go/no-go decision report.

## Generate the Xcode project

This repository uses XcodeGen so the project definition stays reviewable as text.

```sh
brew install xcodegen
xcodegen generate
open QuietDriveLab.xcodeproj
```

## Current backlog

See `docs/STATUS.md`.
