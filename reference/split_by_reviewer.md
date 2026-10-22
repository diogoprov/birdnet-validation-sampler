# Copy each reviewer's clips to their own folder

Copies the cut clips of a manifest with reviewers
([`assign_reviewers()`](https://provetelab.org/sheepdog/reference/assign_reviewers.md))
to `<output_dir>/<reviewer>/<species_folder>/`, one folder tree per
reviewer, ready for the review tab of the BirdNET GUI. Clips with a
second reviewer are copied to both folders. After the review, classify
each reviewer's folder with
[`classify_review()`](https://provetelab.org/sheepdog/reference/classify_review.md).

## Usage

``` r
split_by_reviewer(manifest, clips_dir, output_dir)
```

## Arguments

- manifest:

  Manifest returned by
  [`assign_reviewers()`](https://provetelab.org/sheepdog/reference/assign_reviewers.md).

- clips_dir:

  Folder of the cut clips (the `clips` folder written by
  [`cut_clips()`](https://provetelab.org/sheepdog/reference/cut_clips.md)).

- output_dir:

  Output folder.

## Value

A tibble with `reviewer`, `species_folder`, `clip_file` and `to`,
invisibly.
