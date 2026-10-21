# Positive clips for retraining

Lists the clips confirmed as positive, ready to retrain the classifier.

## Usage

``` r
retraining_clips(validation)
```

## Arguments

- validation:

  Table returned by
  [`classify_review()`](https://provetelab.org/sheepdog/reference/classify_review.md).

## Value

A tibble with `site`, `species_code`, `species_folder`, `clip_file`,
`reviewed_path`, `confidence`, `night`, `recording_hour` and
`source_audio`.
