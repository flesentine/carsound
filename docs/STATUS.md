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
- [ ] #21 Add automatic amplitude search
- [ ] #22 Build adaptive controller

## Verification note

The app and unit-test targets compile successfully in GitHub Actions against the iOS simulator SDK. CI currently uses `build-for-testing`, so it compiles the unit tests but does not execute them. The refined result is the lowest measured point on a 5° digital-phase grid, not a proof of the exact acoustic phase at the phone microphone. Physical iPhone/car testing remains required to establish repeatability and real cancellation performance.
