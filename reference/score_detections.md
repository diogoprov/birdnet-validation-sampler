# Score every detection with the calibration model

Reads the complete BirdNET selection tables (not only the reviewed
clips) and predicts, for each detection, the probability that it is a
true positive. Only species present in the calibration are scored. The
night of each detection is its recording date, or the day before for
recordings that start before `dawn_hour`.

## Usage

``` r
score_detections(tables, fit, min_confidence = 0.1, dawn_hour = 12)
```

## Arguments

- tables:

  Named character vector of selection-table paths, named by site (the
  site names of the calibration).

- fit:

  Model returned by
  [`fit_calibration()`](https://provetelab.org/sheepdog/reference/fit_calibration.md).

- min_confidence:

  Detections below this confidence are not scored.

- dawn_hour:

  Recordings that start before this hour belong to the night before.

## Value

A tibble with `site`, `species`, `date`, `night`, `hour`, `confidence`,
`p_tp`, `begin_path` and `file_offset`.
