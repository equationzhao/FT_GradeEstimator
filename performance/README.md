# Edge 540 performance comparisons

Run controlled A/B comparisons before accepting an optimization. Production and
ordinary regression builds exclude this directory.

`ReferenceView.mc` freezes the personal edition at `7d1987b` as a correctness
oracle. `ControlView` must be generated from the immediately preceding accepted
revision, so each round measures one change.

```sh
mkdir -p bin/perf-control
git show CONTROL_REV:source/FT_GradeEstimatorView.mc \
  | sed 's/GradeEstimatorView/ControlView/g' > bin/perf-control/ControlView.mc
monkeyc -f performance.jungle -d edge540 --unit-test \
  -o bin/Performance.prg -y /path/to/developer_key.der
monkeydo "$PWD/bin/Performance.prg" edge540 -t performanceAA
monkeydo "$PWD/bin/Performance.prg" edge540 -t performanceAB
monkeydo "$PWD/bin/Performance.prg" edge540 -t referenceSampleParity
```

Start the simulator before running these commands. Require the complete all-pass
summary, rather than relying on the runner's exit status.
`performanceAA` compares two instances of the current implementation, regardless
of the historical control revision. Run ordinary correctness tests with
`tests.jungle`; running all tests from `performance.jungle` also works but includes
both full timing suites.

The benchmark-only legacy property resource lets historical controls read
`buffer_length`. Production settings no longer expose that redundant option.
Garmin requires keys to be declared before calling
[`Properties.getValue()`](https://developer.garmin.com/connect-iq/api-docs/Toybox/Application/Properties.html).

## Method

- Run identical control and candidate source first to estimate A/A noise.
- Compile both implementations into the same unit-test executable. Benchmarks
  use metric units and disable FIT output; separate regressions exercise FIT
  registration, failures and recording. These are dense batches, not real-time
  one-second sampling or release-build battery measurements.
- Warm both views, then collect nine A/B pairs per scenario, alternating order.
- Time batches with `System.getTimer()`. Keep setup and logging outside timing.
  Activity-info field assignments remain inside both timed calculation batches.
- Draw into the same native 246 × 106 monochrome bitmap. This includes formatting,
  measurement and rasterization, but excludes physical screen transfer.
- Scenarios: unchanged paused page, changing page, default-window calculation,
  calculation plus drawing, fixed 180-sample calculation, fixed seven-sample
  calculation. Use the same deterministic inputs for both implementations.
- Report paired percentage changes, medians, raw samples, and a bootstrap 95%
  interval. Treat pairs within one simulator process as correlated observations,
  not nine independent physical-device trials.
- Accept CPU improvements only when the paired median exceeds 5%, the interval's
  lower endpoint exceeds 5%, and at least eight of nine pairs improve. Raise this
  threshold if the A/A control exhibits larger systematic variation. Confirm a
  candidate with another run when noise or regressions make the result unclear.
  Initial A/A runs showed up to 3.5% median variation and large cold-drawing
  outliers, so the threshold is 5% and the first drawing scenario receives
  at least 30 seconds of alternating drawing warm-up. Fixed iteration warm-up
  still left large paused-page outliers in round 2; repeat suspect measurements.
- Memory-only improvements may be accepted when storage is deterministically
  reduced, allocation measurements confirm the reduction, and timing does not
  show a clear regression. Memory readings around construction and first drawing
  are observations of the shared runtime, not a guaranteed peak measurement.
- Compare every sample against the frozen reference for slope, quality, adaptive
  window, VAM, cumulative distances, maximum grade, ascent, and status.

Drawing caches must also preserve first draw before `compute()`, layout and unit
changes, threshold changes, invalid values, timer transitions, and FIT errors.
Keep these correctness cases in the existing regression suite.

Simulator timings establish relative performance for these workloads. They do
not establish real-device battery savings or total firmware CPU use.

## Additional workloads

`extendedPerformanceAB` and `extendedPerformanceAA` use the same nine-pair rule:

| Key | Workload |
| --- | --- |
| 6 | Adaptive 7–20 window, alternating climbs, descents and altitude noise |
| 7 | Same input with adaptive 7–180 window |
| 8 | Native FIT grade recording enabled, with pause/resume callbacks and stopped samples |
| 9 | Default calculation with inputs generated before timing |
| 10 | Adaptive 7–180 calculation with inputs generated before timing |
| 11 | Imperial dynamic drawing in a 246 × 160 field |
| 12 | View construction plus first drawing, alternating units and field sizes |
| 13 | Repeated size and unit changes, including the undersized-field hint |

Keys 9–10 still time input assignment and `compute()`, but not input generation;
their times must not be compared to the original timing boundary. Key 12 includes
construction because an isolated first draw is too short for the millisecond timer.
Four native bitmaps cover 246 × 78, 246 × 106, 246 × 160 and 200 × 70 fields.
The first compute and first drawing workload each receive 30 seconds of warm-up.
FIT registration happens after constructing test views, outside measured batches;
both views must have real native fields and no registration or write error.
They share one native field registration and write sequentially, because the
simulator rejects duplicate field IDs within one application. This measures native
`setData()` calls, not FIT-file serialization or transfer to a physical device.

`adaptiveWindowDiagnostics` reports unchanged/growing/shrinking windows and their
length distribution separately from timing. `adaptiveReferenceParity` compares
9,600 additional samples against the frozen reference, including changing windows,
pause/resume and slopes above the display clamp. Diagnostics never run inside a
timed batch. Keep the original six workloads and report their results separately.
