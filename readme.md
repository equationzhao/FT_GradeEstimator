# Grade 540 Personal

A lightweight Garmin Edge 540 data field with one full-width, three-column layout:

| Left | Center | Right |
| --- | --- | --- |
| Current grade | Light climbing distance | Current VAM |
| Maximum grade | Hard climbing distance | Total ascent |

The status row shows calculation quality, buffering, pause/stop state, and FIT errors. Distances, ascent, and VAM follow the device's metric or imperial units.

Total ascent comes directly from Garmin's current activity data. It updates independently of grade calculation, remains visible while stopped or paused, and clears when the activity resets. A temporarily unavailable reading retains the last valid total; before the first reading, the field shows `--`.

Light and hard distances use configurable grade thresholds (3.5% and 8% by default) and count only accepted samples while the activity timer runs. Maximum grade uses the configured fit-quality threshold. The sample buffer holds only the configured maximum fit window. Stops, missing sensor data, altitude jumps, and excessive sampling gaps restart the grade estimator without clearing activity totals.

## FIT recording

- **Enable FIT Logging** records light/hard climbing distance in the activity summary.
- **Log Gradient Data** additionally records the estimated grade, and is disabled by default.
- Native total ascent is already recorded by Garmin, so this field does not add a duplicate ascent field.

The edition excludes average VAM, held-grade windows, lap-average grade, graphs, alternative layouts, and other device targets. It retains the adaptive slope estimator, bounded settings, missing-data handling, and independent FIT field retries.

## Install and layout

Build for `edge540`, copy the signed `.prg` into the device's `Garmin/Apps` directory, and add **Grade 540 Personal** to a cycling data screen. Use a full-width field at least 220 × 78 pixels (for example, a row in the three- or four-field full-width screen layouts). A field that is too small displays a layout hint.

This edition uses its own application ID, so it can coexist with Adaptive Grade Plus. The complete edition remains on the repository's `main` branch.

## Build

Requirements: Connect IQ SDK, the Edge 540 device package, Java, and a Connect IQ developer signing key.

```sh
mkdir -p bin
monkeyc -f monkey.jungle -d edge540 -r \
  -o bin/Grade540Personal.prg -y /path/to/developer_key.der
```

## Regression tests

Open the Connect IQ simulator and wait for its window to finish loading, then run:

```sh
monkeyc -f tests.jungle -d edge540 --unit-test \
  -o bin/PersonalRegression.prg -y /path/to/developer_key.der
monkeydo "$PWD/bin/PersonalRegression.prg" edge540 -t
```

Require the complete all-pass summary. SDK 9.2 may return exit code 1 even when its test summary reports success. Tests cover grade and distance calculations, activity transitions, native ascent, missing data, settings bounds, FIT failures and capacity, and a two-hour input sequence. Production builds exclude the tests.

Based on [Adaptive Grade Plus by FrederikTheisen](https://github.com/FrederikTheisen/FT_GradeEstimator).
