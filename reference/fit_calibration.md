# Fit the calibration model

Fits a calibration model to all the reviewed clips. The species and site
levels of `validations` are stored with the model, so that
[`score_detections()`](https://provetelab.org/sheepdog/reference/score_detections.md)
can score new detections.

## Usage

``` r
fit_calibration(validations, formula)
```

## Arguments

- validations:

  Table returned by
  [`read_validations()`](https://provetelab.org/sheepdog/reference/read_validations.md).

- formula:

  Model formula, usually the best one of
  [`compare_calibration_models()`](https://provetelab.org/sheepdog/reference/compare_calibration_models.md).

  A model with random effects whose fit is singular (a variance
  estimated at zero or a correlation at +-1) raises a warning: the fixed
  effects and the predictions can still be used, but the variance
  components on the boundary should not be interpreted, and a simpler
  model may predict as well. Check them with
  [`lme4::VarCorr()`](https://rdrr.io/pkg/nlme/man/VarCorr.html).

## Value

A `glm` (no random effects) or `glmerMod` model, with the attribute
`sheepdog_levels` (the species and site levels), used by
[`score_detections()`](https://provetelab.org/sheepdog/reference/score_detections.md)
and
[`plot_calibration()`](https://provetelab.org/sheepdog/reference/plot_calibration.md).
