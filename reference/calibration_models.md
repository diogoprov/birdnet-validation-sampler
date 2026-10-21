# Candidate calibration models

The family of logistic calibration models compared by
[`compare_calibration_models()`](https://provetelab.org/sheepdog/reference/compare_calibration_models.md),
from a single logistic regression on the logit of the confidence score
to a binomial GLMM with random slopes by species and a site x species
intercept.

## Usage

``` r
calibration_models()
```

## Value

A named list of formulas: `m0_global`, `m1_species_intercept`,
`m2_species_slope`, `m3_plus_site` and `m4_species_x_site`.
