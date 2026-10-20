# Edge 540 optimization results

Measurements use the Connect IQ 9.2 Edge 540 simulator on October 20, 2026.
Percentages below are medians of paired reductions in elapsed time. Each round
compares one candidate against the immediately preceding accepted implementation.
They are not additive.

The initial personal edition is `7d1987b`. All retained rounds preserve its numerical
results exactly for the deterministic parity workload. Production builds exclude
the benchmark, reference implementation, and control implementation.

| Round | Change | Main result | Decision |
| --- | --- | --- | --- |
| 0 | Identical-source A/A controls | Cold drawing had large outliers; warm median variation reached 3.5% | Require a 95% interval above 5% and at least 8/9 winning pairs; extend warm-up |
| 1 | Font metrics and static label fitting | Changing-page rendering 18.0% faster (95% interval 17.0–18.9%); combined calculation/drawing 7.8% faster | Keep; approximately 504 additional bytes observed during view setup |
| 2 | Merge coordinate generation and regression sums | Default calculation 13.0% faster (9.6–15.2%); fixed 180-sample calculation 11.1% faster | Keep; no additional storage |
| 3 | Reuse slope when candidate windows match | Fixed seven-sample calculation 22.0% faster; fixed 180-sample calculation 26.9% faster; default-window change within noise | Keep; no additional storage |
| 4 | Reuse fitted fonts for unchanged value/status text | Paused-page rendering 11.3% faster (9.7–13.0%); dynamic-page improvement did not clear the strict confidence threshold | Keep; approximately 480 additional bytes observed during view setup |
| 5 | Cache formatted strings by exact input and units | Changing-page rendering **12.7% slower** (11.2–14.0% slowdown); paused rendering had no improvement | Reject and restore round 4; preserve native rounding behavior |
| 5b | Embed units/prefixes in numeric format patterns | SDK raised `Invalid Value: Unexpected input to format`; correctness tests rejected the candidate before timing | Reject and restore round 4 |
| 6 | Match buffer capacity to the maximum fit window | Default view allocation reduced by 672 bytes; fixed seven-sample allocation reduced by 1,256 bytes; timing changes within noise | Keep for memory savings; remove the redundant buffer-length setting |
| 7 | Replace nested samples with two flat arrays | Default calculation 10.1% faster (9.2–10.6%); fixed 180-sample calculation 11.2% faster; allocation reduced by 656 bytes at the default window and 6,256 bytes at 180 samples | Keep |

## First-series comparison with the original personal edition

The first series ended at production source `badcd7e`, compared with `7d1987b`. The first
aggregate run had large rendering outliers; a repeat using the **same executable**
confirmed all six workloads. Every scenario won all nine pairs in that repeat.
The table reports the repeat; both runs are retained in `results/`.
The final identical-source A/A check had paired median differences from −1.49%
to +0.88%, with no scenario meeting the improvement rule. Its raw pairs are also
retained in `results/final-aa.json`.

| Workload | Original batch median (ms) | Final batch median (ms) | Paired time reduction | 95% interval |
| --- | ---: | ---: | ---: | --- |
| Paused-page rendering | 191 | 134 | 29.8% | 28.9–33.0% |
| Changing-page rendering | 202 | 154 | 23.8% | 19.9–25.2% |
| Default-window calculation | 581 | 467 | 19.0% | 17.8–20.8% |
| Calculation plus rendering | 444 | 353 | 20.1% | 18.5–20.9% |
| Fixed 180-sample calculation | 1114 | 658 | 41.5% | 40.7–43.0% |
| Fixed seven-sample calculation | 287 | 187 | 34.4% | 33.8–36.6% |

Observed view setup allocation was 2,400 → 2,056 bytes at the default window,
and 9,728 → 4,456 bytes at 180 samples. These deltas are distinct from the
release executable size and whole-app memory reported by the simulator.
The signed release grew from 14,444 to 14,812 bytes (+368 bytes). The simulator's
idle four-row screen reported approximately 13.7 → 13.8 KB overall, so whole-app
memory is essentially unchanged; this is not a claim of overall memory reduction.
The release launched successfully and rendered all six fields after changing
from a full-screen field to the compact four-row layout.

The accepted implementation passed 26 regression tests and exact parity across
7,200 samples in four configurations. Performance and frozen-reference checks
live in the separate benchmark.

## Reproducibility and limits

See [the benchmark method](README.md) and the raw paired timings in `results/`.
Scenario keys are `0` paused drawing, `1` changing drawing, `2` default calculation,
`3` calculation plus drawing, `4` fixed 180-sample calculation, and `5` fixed
seven-sample calculation.

Rounds 0–1 exposed startup rendering noise. Round 2 added fixed-count drawing
warm-up, which was still insufficient for the paused scenario. Round 3 onward
uses at least 30 seconds of alternating drawing warm-up. Compare A/B pairs within
a round; do not compare raw elapsed times across different warm-up revisions.

Memory deltas around view creation and first drawing are shared-runtime
observations, not peak-memory or whole-program measurements. Font caches trade
a small amount of retained memory for less repeated measurement. Simulator
performance does not establish physical-device battery savings.


## Follow-up optimization rounds

The follow-up series starts from `f634e28` (production source `badcd7e`). New
workloads are defined in README.md; their A/A paired medians ranged from −0.42%
to +1.29%, with no false improvements. The initial FIT fixture attempted duplicate
native field registrations and failed before timing that scenario. The corrected
fixture shares one real native field set between the two sequential writers.
Ordinary regressions now include 27 tests. Frozen-reference checks cover 16,800
samples: the previous 7,200 plus 9,600 adaptive, pause/resume and clamped-slope
samples. Each retained round must pass both suites.

| Round | Change | Result against preceding accepted source | Decision |
| --- | --- | --- | --- |
| 8 | Skip candidate selection for fixed windows | Fixed 180: 35.22% reduction (95% interval 34.49–36.03%); fixed 7: 31.52% (30.98–33.16%). Both 9/9 wins. Default calculation −0.66%; other workloads within the 5% threshold. | Keep |
