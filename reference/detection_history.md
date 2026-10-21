# Nightly detection history

Aggregates the scored detections by site x species x night. A night has
a detection when at least `min_detections_night` detections have a
calibrated probability \>= `p_min`; the columns `detection_k1` to
`detection_k3` give the same rule with k = 1, 2 and 3, as a sensitivity
analysis.

## Usage

``` r
detection_history(scored, p_min = 0.95, min_detections_night = 1)
```

## Arguments

- scored:

  Table returned by
  [`score_detections()`](https://provetelab.org/birdnet-validation-sampler/reference/score_detections.md).

- p_min:

  Threshold on the calibrated probability (not on the confidence score).

- min_detections_night:

  Repetition rule: minimum number of reliable detections for a night
  with detection.

## Value

A tibble with `site`, `species`, `night`, `n_detections`, `n_reliable`,
`p_tp_max`, `detection_k1`, `detection_k2`, `detection_k3` and
`detection`.
