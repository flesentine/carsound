# QuietDrive Lab status

## Completed

- [x] #1 Create native iOS project scaffold
- [x] #2 Set up audio session
- [x] #3 Build microphone capture
- [x] #4 Build raw audio diagnostics screen
- [x] #5 Implement FFT processing
- [x] #6 Build live spectrum graph
- [x] #7 Add spectrum smoothing
- [x] #8 Implement noise-floor measurement
- [x] #9 Build dominant-frequency detection
- [x] #10 Add persistent-tone detection
- [x] #11 Add low-frequency-only analysis mode
- [x] #12 Build tone generator
- [x] #13 Add manual output-level control
- [x] #14 Add manual phase control
- [x] #15 Build Lab cancellation control screen
- [x] #16 Measure target-frequency energy
- [x] #17 Create before/after measurement
- [x] #18 Add experiment recorder
- [x] #19 Add automatic phase sweep
- [x] #20 Refine phase search
  - new reusable PhaseRefinementModel
  - refinement starts from the best coarse phase found by #19
  - Stage 1 searches coarse winner ±30° at 15° spacing
  - Stage 2 searches the Stage-1 winner ±10° at 5° spacing
  - phase grids normalize correctly across the 0°/360° boundary
  - the same existing baseline, target frequency, and output level are held fixed through both refinement stages
  - each refinement phase uses the same 350 ms settling interval as the coarse sweep
  - each phase then collects 20 valid target-energy readings at 10 Hz
  - treatment windows reuse the existing linear-power averaging and before/after comparison math
  - every fine-search treatment is automatically saved to durable experiment history
  - fine-search progress reports stage, phase index, angle, settling, and sample count
  - Stage 1 and Stage 2 result tables are shown separately in the Cancellation Lab
  - each stage identifies its own lowest-energy candidate
  - final refined phase is selected by lowest treatment-band energy across both stages
  - treatment variability remains the tie-breaker for effectively equal energy measurements
  - Apply Best Refined Phase control
  - fine refinement automatically mutes generated output when complete
  - Cancel Fine Search immediately cancels the active refinement and mutes output
  - MUTE NOW cancels both coarse and fine searches before muting
  - Stop All cancels A/B measurement, coarse sweep, and fine refinement before stopping tone/capture
  - conflicting manual/measurement controls are locked during refinement
  - starting or resetting a new coarse sweep clears stale fine-search state
  - tests cover 15° Stage-1 grid, 5° Stage-2 grid, wrap-around behavior at 0°/360°, and best-result selection across both stages
  - full app + unit-test simulator build-for-testing green in GitHub Actions

## Milestone status

### Milestone 1 — Hear the car
- [x] #1–#11 complete

### Milestone 2 — Fight one frequency
- [x] #12 Build tone generator
- [x] #13 Add manual output-level control
- [x] #14 Add manual phase control
- [x] #15 Build Lab cancellation control screen
- [x] #16 Measure target-frequency energy
- [x] #17 Create before/after measurement
- [x] #18 Add experiment recorder
- [x] #19 Add automatic phase sweep
- [x] #20 Refine phase search
- [x] #21 Add automatic amplitude search
  - new reusable AmplitudeSearchModel
  - holds the best refined phase from #20 fixed during amplitude search
  - uses the user's current selected output level as an additional search ceiling
  - search never raises output above that user-selected ceiling
  - existing 0.02 PCM hard amplitude ceiling remains enforced underneath the search ceiling
  - minimum automatic search level is 2%
  - Stage 1 performs a coarse 10%-step search from low output up to the selected ceiling
  - non-round ceilings are included exactly, e.g. a 42% ceiling tests 10/20/30/40/42%
  - Stage 2 searches around the coarse winner within ±10% using 2% steps
  - fine-stage levels are clamped to the user-selected ceiling and never exceed it
  - same baseline, target frequency, and refined phase are held fixed through the search
  - each output level gets the standard 350 ms settling interval
  - each output level then collects 20 valid target-energy readings at 10 Hz
  - treatment windows reuse existing linear-power averaging and before/after comparison math
  - every amplitude-search treatment is automatically saved to durable experiment history
  - live progress reports stage, level index, output percent, settling, and sample count
  - Stage 1 and Stage 2 result tables show output level, target-band energy, and reduction/increase versus baseline
  - best output is selected by lowest measured treatment-band energy
  - lower variability breaks equal-energy ties
  - lower output level breaks ties when both energy and variability are effectively equal
  - Apply Best Output Level control
  - automatic search applies the refined phase before level testing
  - search automatically mutes generated output when complete
  - Cancel Amplitude Search immediately cancels and mutes
  - MUTE NOW cancels coarse phase, fine phase, and amplitude search before muting
  - Stop All cancels all active measurement/search work before stopping capture/output
  - conflicting manual and experiment controls are locked during amplitude search
  - starting a new coarse/fine phase search clears stale amplitude-search state
  - tests cover coarse grid generation, non-round ceilings, ceiling enforcement, minimum level, fine 2% grid, ceiling clamping, best-energy selection, and lower-output tie-breaking
  - full app + unit-test simulator build-for-testing green in GitHub Actions
- [ ] #22 Build adaptive controller

## Verification note

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. CI currently uses `build-for-testing`, so it compiles the unit tests but does not execute them. The refined phase and amplitude result are experimentally selected digital settings, not proof of exact acoustic phase or calibrated acoustic SPL at the phone microphone. The automatic amplitude search stays below both the user's selected search ceiling and the app's hard digital ceiling. Physical iPhone/car testing remains required to establish repeatability and real cancellation performance.
