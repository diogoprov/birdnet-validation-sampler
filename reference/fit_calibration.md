# Fit the calibration model

Fits a calibration model to all the reviewed clips. The species and site
levels of `validations` are stored with the model, so that
[`score_detections()`](https://provetelab.org/birdnet-validation-sampler/reference/score_detections.md)
can score new detections.

## Usage

``` r
fit_calibration(validations, formula)
```

## Arguments

- validations:

  Table returned by
  [`read_validations()`](https://provetelab.org/birdnet-validation-sampler/reference/read_validations.md).

- formula:

  Model formula, usually the best one of
  [`compare_calibration_models()`](https://provetelab.org/birdnet-validation-sampler/reference/compare_calibration_models.md).

## Value

A `glm` (no random effects) or `glmerMod` model, with the attribute
`sheepdog_levels` (the species and site levels), used by
[`score_detections()`](https://provetelab.org/birdnet-validation-sampler/reference/score_detections.md)
and
[`plot_calibration()`](https://provetelab.org/birdnet-validation-sampler/reference/plot_calibration.md).
