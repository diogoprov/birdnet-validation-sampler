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

- n_train:

  Training sizes per site x species.

- n_reps:

  Repetitions per training size.

- seed:

  Seed of the draws. The global random number generator is left as it
  was.

## Value

A tibble with `n_per_cell`, `auc_mean` and `auc_sd`.
