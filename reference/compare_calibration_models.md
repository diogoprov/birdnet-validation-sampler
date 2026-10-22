# Compare calibration models by cross-validation

Fits each candidate model with k-fold cross-validation and scores the
predicted probabilities on the held-out folds. Folds are stratified
within site x species, so every level appears in both the training and
the test sets. Models with random effects need the 'lme4' package.

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

A tibble with `model`, `formula`, `auc_mean`, `auc_sd`, `n_failed`
(folds whose fit failed, left out of the means), `logloss_mean`,
`logloss_sd`, `brier_mean`, `brier_sd`, `cal_intercept` and `cal_slope`
(means over the folds), `prop_singular` (share of the fold fits that
were singular) and `complexity` (position of the model in `models`),
ordered from the highest mean AUC. Failed folds also raise a warning.

## Details

The AUC measures discrimination (whether true detections get higher
probabilities than false ones). The log-loss and the Brier score are
proper scoring rules: they reward probabilities close to the observed
outcomes, which is what matters when the probabilities are compared with
`p_min` (Gneiting & Raftery 2007,
[doi:10.1198/016214506000001437](https://doi.org/10.1198/016214506000001437)
). The calibration intercept and slope come from a logistic regression
of the verdicts on the logit of the predicted probabilities in each test
fold: a well calibrated model has intercept 0 and slope 1; a slope below
1 means probabilities too extreme (overfitting).
