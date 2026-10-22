# Select the calibration model

Picks a model from the table of
[`compare_calibration_models()`](https://provetelab.org/sheepdog/reference/compare_calibration_models.md).

## Usage

``` r
select_calibration_model(
  comparison,
  rule = c("best_auc", "one_se_logloss"),
  k_folds = 5
)
```

## Arguments

- comparison:

  Table returned by
  [`compare_calibration_models()`](https://provetelab.org/sheepdog/reference/compare_calibration_models.md).

- rule:

  Selection rule.

- k_folds:

  Number of folds of the comparison (for the standard error).

## Value

The name of the selected model.

## Details

- `"best_auc"`: the model with the highest mean AUC (the rule of
  [`calibrate()`](https://provetelab.org/sheepdog/reference/calibrate.md)
  in 2.x).

- `"one_se_logloss"`: among the models whose mean log-loss is within one
  standard error (`logloss_sd / sqrt(k_folds)`) of the lowest, the
  simplest (lowest `complexity`); models singular in most folds are left
  out, unless all are, which raises a warning. The log-loss rewards
  correct probabilities, not only their ranking, and the one-standard-
  error rule prefers the simpler model when the data cannot tell the
  candidates apart. This rule will be the default of
  [`calibrate()`](https://provetelab.org/sheepdog/reference/calibrate.md)
  in 3.0.0.
