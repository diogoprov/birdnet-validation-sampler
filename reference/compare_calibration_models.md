# Compare calibration models by cross-validation

Fits each candidate model with k-fold cross-validation and reports the
mean and standard deviation of the AUC on the held-out folds. Folds are
stratified within site x species, so every level appears in both the
training and the test sets. Models with random effects need the 'lme4'
package.

## Usage

``` r
compare_calibration_models(
  validations,
  models = calibration_models(),
  k_folds = 5,
  seed = 2026
)
```

## Arguments

- validations:

  Table returned by
  [`read_validations()`](https://provetelab.org/sheepdog/reference/read_validations.md).

- models:

  Named list of model formulas.

- k_folds:

  Number of folds.

- seed:

  Seed of the fold assignment. The global random number generator is
  left as it was.

## Value

A tibble with `model`, `formula`, `auc_mean` and `auc_sd`, ordered from
the highest mean AUC.
