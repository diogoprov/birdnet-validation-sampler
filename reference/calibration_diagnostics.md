# Convergence diagnostics of a Bayesian calibration model

Reports the largest R-hat, the smallest bulk and tail effective sample
sizes and the number of divergent transitions of a model fitted with
`engine = "brms"`, and whether they pass the usual limits.

## Usage

``` r
calibration_diagnostics(fit, rhat_max = 1.01, ess_min = 400)
```

## Arguments

- fit:

  Model returned by
  [`fit_calibration()`](https://provetelab.org/sheepdog/reference/fit_calibration.md)
  with `engine = "brms"`.

- rhat_max:

  Largest acceptable R-hat.

- ess_min:

  Smallest acceptable bulk and tail effective sample size.

## Value

A one-row tibble with `max_rhat`, `min_ess_bulk`, `min_ess_tail`,
`n_divergent` and `ok`.
