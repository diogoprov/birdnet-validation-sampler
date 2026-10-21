# Precision by confidence bin

Precision (share of positive verdicts) of the reviewed clips, by site,
species and confidence bin. Clips without confidence (whole recordings
of `"random_recordings"`) are left out.

## Usage

``` r
precision_by_bin(validation, bins = seq(0.1, 1, by = 0.1), min_n = 15)
```

## Arguments

- validation:

  Table returned by
  [`classify_review()`](https://provetelab.org/birdnet-validation-sampler/reference/classify_review.md).

- bins:

  Breaks of the confidence bins (left-closed).

- min_n:

  Minimum of reviewed clips for a bin to be taken seriously; bins with
  fewer are flagged in `low_support`.

## Value

A tibble with `site`, `species_folder`, `bin`, `n_reviewed`,
`n_positive`, `precision` and `low_support`.
