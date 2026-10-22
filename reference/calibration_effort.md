# Effort curve of the calibration

How many reviewed clips per site x species are needed to calibrate well?
For each training size, draws that many clips per cell (keeping at least
five for testing), fits the model and computes the AUC on the remaining
clips. Repetitions with fewer than 50 test clips, or whose fit fails,
are dropped.

## Usage

``` r
calibration_effort(
  validations,
  formula,
  n_train = c(5, 10, 15, 20, 25, 30),
  n_reps = 50,
  seed = 2026
)
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

- n_train:

  Training sizes per site x species.

- n_reps:

  Repetitions per training size.

- seed:

  Seed of the draws. The global random number generator is left as it
  was.

## Value

A tibble with `n_per_cell` (the requested training size), `auc_mean`,
`auc_sd`, `n_train_mean` (mean clips per cell actually used for
training), `n_test_mean` (mean size of the test set) and `n_failed`
(repetitions dropped).

## Details

Cells with fewer than `n_train + 5` clips contribute all but five of
their clips, so the training size actually used can be below `n_train`;
it is reported in `n_train_mean`, with a warning. The test set shrinks
as `n_train` grows (`n_test_mean`), which widens `auc_sd`.
