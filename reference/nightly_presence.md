# Confirmed presence by night

Summarises the verdicts by site, species and night. A night is
`"confirmed"` when at least one clip is positive,
`"not_detected_in_reviewed"` when clips were reviewed but none was
positive, and `"not_reviewed"` otherwise.

## Usage

``` r
nightly_presence(validation)
```

## Arguments

- validation:

  Table returned by
  [`classify_review()`](https://provetelab.org/birdnet-validation-sampler/reference/classify_review.md).

## Value

A tibble with `site`, `species_folder`, `night`, `n_clips`,
`n_reviewed`, `n_positive`, `presence` and `max_confidence_positive`.
