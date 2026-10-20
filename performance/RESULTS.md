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
| 9 | Reuse candidate statistics and scratch distances when the final window is unchanged | Default calculation: 31.95% reduction (30.17–33.68%); calculation + drawing: 16.81% (15.79–18.10%); precomputed inputs: 32.02% first run, 31.86% repeat. No meaningful gain or regression for the low-hit-rate adaptive workload or FIT workload. | Keep; +32 bytes observed during view setup |
| 10 | Increment and wrap regression indices instead of repeated modulo | Fixed 180: 11.79% reduction (10.76–12.44%); fixed 7: 6.92% (5.34–17.20%), both 9/9 wins. Default calculation 2.61%, below the acceptance threshold. | Keep for fixed-window gains; no additional view storage |
| 11 | Cache cell geometry and invalidate font caches once per layout change | Dynamic drawing 0.68% (0.00–2.58%), paused drawing 1.54%, imperial tall drawing 1.26%: none clears 5%. Construction + first draw **9.68% slower** (6.45–13.33% slowdown), all nine pairs slower; size/unit switching 3.83% slower. View allocation +216 bytes. | Reject and restore round 10, including the previous font-cache contract |

Round 9's first extended run had cold-construction outliers (paired median −3.23%,
interval −21.43–3.03%). Repeating the **same executable** produced 0.00% with an
interval of −3.33–3.12%; both runs are retained. This is not a demonstrated cold
startup regression or improvement. The ordinary and frozen-reference suites passed.

Round 10's first two extended runs retained large first-scenario startup outliers.
The extended compute warm-up was increased from 30 to 60 seconds, and focused
7–20 checks were added. The longer A/A run gave 0.46% (−1.40–1.39%); the A/B run
gave 4.07% (3.56–4.52%), all nine pairs faster, below the 5% improvement threshold
and with no measured regression. The other adaptive results are not promoted as
confirmed gains: the 7–180 workload dropped from 6.46% to 4.75% on repeat; the
precomputed 7–180 interval also crossed 5%. All original runs remain available.
A simulator load stalled before producing test output and was restarted before
the focused checks; this was an infrastructure interruption, not a test failure.

Round 11 passed all 27 ordinary tests and 16,800 reference samples, but failed the
performance gate. Its layout cache and supporting changes to internal cache tests
were reverted. The independent first-draw, layout-switch and unit-change regression
added with the benchmark remains. No formatting cache or partial-redraw pipeline
was introduced.


## Follow-up final comparison

Production source `e95fef0` was compared directly with `f634e28` using the final
harness. These are measured aggregate changes, not sums of round percentages.
The final build passed all 27 ordinary regressions and exact frozen-reference
parity on all 16,800 samples. The retained changes are rounds 8–10; round 11 is
absent from production.

| Workload | Starting median (ms) | Final median (ms) | Paired time reduction | 95% interval | Winning pairs |
| --- | ---: | ---: | ---: | --- | ---: |
| Default calculation, 1,200 samples | 467 | 307 | 33.98% | 31.48–35.27% | 9/9 |
| Calculation + drawing, 500 samples | 345 | 279 | 18.80% | 15.77–20.58% | 8/9 |
| Fixed 180-sample window, 240 samples | 641 | 369 | 42.54% | 42.28–42.90% | 9/9 |
| Fixed seven-sample window, 1,200 samples | 181 | 118 | 34.83% | 34.08–35.56% | 9/9 |
| Changing adaptive 7–180 window, 1,200 samples | 313 | 293 | 6.75% | 5.43–7.28% | 9/9 |
| Precomputed default inputs, 600 samples | 227 | 151 | 33.91% | 33.33–34.93% | 9/9 |
| Precomputed adaptive 7–180 inputs, 600 samples | 203 | 186 | 7.66% | 7.14–8.46% | 9/9 |

Changing adaptive 7–20 input (4.37%) and native FIT recording with pause/resume
(4.39%) did not clear the 5% gate. Paused, dynamic and imperial drawing, and cold
construction/first drawing had 0.00% paired median change. Size/unit switching was
−0.56% (−1.14–1.13%). No scenario showed a confirmed regression. See
`followup-final-vs-start*.json` for all 14 workloads and the original pairs.
Default view setup allocation increased from 2,056 to 2,088 bytes (+32 bytes).


The final six-scenario identical-source A/A check ranged from −0.34% to +0.37%
in paired median difference, with no false improvements. Its raw pairs are in
`followup-final-aa.json`. The separate longer-warm-up adaptive A/A check is in
`round10-long-warm-aa.json`; the eight-workload starting calibration is in
`extended-baseline-aa.json`.

The diagnostic default workload kept its window unchanged for 1,184/1,200 samples
(98.67%), with 11 increases and five decreases. The two deliberately changing
workloads kept their windows unchanged for only 69/1,200 and 68/1,200 samples
(5.75% and 5.67%). These counters were collected in a separate diagnostic run;
production and timed batches contain no counters.

The signed Edge 540 release is 15,292 bytes, up from 14,812 (+480 bytes). It launched
successfully and displayed all six fields after switching from one full-screen
field to the four-row layout. The simulator showed approximately 14.3 KB overall,
versus 13.8 KB before this series. Both retained calculation improvements and their
small memory/code-size cost should be considered. There is no physical-device
or battery-life measurement.
