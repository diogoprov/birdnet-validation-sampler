# Read the validation tables for calibration

Stacks the `validation_by_clip.csv` tables of several sites (output of
[`post_validation()`](https://provetelab.org/sheepdog/reference/post_validation.md))
and keeps the clips with a positive or negative verdict and a confidence
score. Tables written by v1.2.0 (`validacao_por_clipe.csv`) are also
read. Whole-recording clips of `"random_recordings"` have no confidence
and are left out.

## Usage

``` r
read_validations(files, site_map = NULL, keep = NULL)
```

## Arguments

- files:

  Paths to the `validation_by_clip.csv` files. Missing files are skipped
  with a warning.

- site_map:

  Optional named character vector to fix diverging site names, as
  `c(old = "new")`, e.g. `c(BEP2 = "BEP")`.

- keep:

  Optional character vector of input columns to retain, e.g.
  `c("source_audio", "night")` for grouped cross-validation. Missing
  columns raise an error rather than silently falling back to clip
  folds.

## Value

A tibble with `site` and `species` (factors; `species` is the species
folder code), `confidence`, `logit_conf` (logit of the confidence,
bounded at 1e-4 and 1 - 1e-4) and `tp` (1 = true positive, 0 = false
positive), plus the columns requested in `keep`.
