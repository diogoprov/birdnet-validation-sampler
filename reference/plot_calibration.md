# Plot the calibration curves

Calibrated probability of a true detection against the confidence score,
one panel per species and one line per site, with the observed precision
by confidence bin as points. Needs the 'ggplot2' package.

## Usage

``` r
plot_calibration(
  fit,
  validations,
  min_confidence = 0.1,
  p_min = 0.95,
  model_name = ""
)
```

## Arguments

- fit:

  Model returned by
  [`fit_calibration()`](https://provetelab.org/sheepdog/reference/fit_calibration.md).

- validations:

  Table returned by
  [`read_validations()`](https://provetelab.org/sheepdog/reference/read_validations.md).

- min_confidence:

  Detections below this confidence are not scored.

- p_min:

  Threshold on the calibrated probability (not on the confidence score).

- model_name:

  Name shown in the subtitle.

## Value

A ggplot object.
