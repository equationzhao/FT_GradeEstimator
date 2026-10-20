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
monkeydo "$PWD/bin/Performance.prg" edge540 -t
```

Start the simulator before running these commands. Require the complete all-pass
summary, rather than relying on the runner's exit status.

## Method

- Run identical control and candidate source first to estimate A/A noise.
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
  5,000 extra warm-up iterations per implementation.
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
