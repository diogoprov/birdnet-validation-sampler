# Calibration curves of posterior (or prior) draws

Draws the population-level calibration curve, P(TP) against the score,
for `n_draws` draws of a Bayesian calibration model, without the species
and site effects. With a model from
[`prior_predictive_calibration()`](https://provetelab.org/sheepdog/reference/prior_predictive_calibration.md)
it shows what the prior implies on the probability scale (a prior
predictive check); with a fitted model, the uncertainty of the curve.
Needs the 'ggplot2' package.

## Usage

``` r
plot_calibration_draws(fit, n_draws = 100, p_min = 0.95, seed = 2026)
```

## Arguments

- fit:

  Model returned by
  [`fit_calibration()`](https://provetelab.org/sheepdog/reference/fit_calibration.md)
  with `engine = "brms"` or by
  [`prior_predictive_calibration()`](https://provetelab.org/sheepdog/reference/prior_predictive_calibration.md).

- n_draws:

  Number of curves.

- p_min:

  Threshold drawn as a dashed line.

- seed:

  Seed of the choice of draws. The global random number generator is
  left as it was.

## Value

A ggplot object.
