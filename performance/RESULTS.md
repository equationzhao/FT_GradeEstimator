# Edge 540 optimization results

Measurements use the Connect IQ 9.2 Edge 540 simulator on October 20, 2026.
Percentages below are medians of paired reductions in elapsed time. Each round
compares one candidate against the immediately preceding accepted implementation.
They are not additive.

The initial personal edition is `7d1987b`. All rounds preserve its numerical
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
