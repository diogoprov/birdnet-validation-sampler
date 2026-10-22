# Build the training folders for BirdNET-Analyzer

Copies the reviewed clips into the folder layout that the training
script of BirdNET-Analyzer expects: one folder per class, named after
the label (`species_code`, so the retrained classifier keeps the labels
of the current one), with the negatives of a class in a folder with the
same name prefixed by `-`. Clips of the sites in `test_sites` go to a
separate `test` folder, to be passed as `--test_data`, so that the new
classifier is evaluated on sites it was not trained on.

## Usage

``` r
build_training_set(
  validation,
  output_dir,
  test_sites = NULL,
  negatives = TRUE,
  min_files = 100
)
```

## Arguments

- validation:

  Reviewed clips, as returned by
  [`classify_review()`](https://provetelab.org/sheepdog/reference/classify_review.md),
  [`post_validation()`](https://provetelab.org/sheepdog/reference/post_validation.md)
  (`$validation`) or
  [`read_validation_tables()`](https://provetelab.org/sheepdog/reference/read_validation_tables.md).
  It needs `site`, `species_code`, `clip_file`, `verdict` and
  `reviewed_path` (the path where the review left each clip).

- output_dir:

  Output folder; `train/` and, with `test_sites`, `test/` are created in
  it.

- test_sites:

  Sites held out for testing. `NULL` puts every clip in `train/`.

- negatives:

  Copy the negative clips into `-<species_code>` folders.

- min_files:

  Minimum number of positive training files per class below which a
  warning is raised.

## Value

A tibble with one row per copied clip: `site`, `species_code`,
`verdict`, `set` (`"train"` or `"test"`), `class_folder`, `clip_file`,
`source_audio`, `clip_start`, `clip_end`, `from` and `to`, invisibly.

## Details

The layout follows the documentation of BirdNET-Analyzer (version 2.4.0,
`birdnet_analyzer.train`), which also recommends at least 100 files per
species; classes below `min_files` in the training set raise a warning.
Whole-recording clips of `"random_recordings"` (longer than 3 s,
`confidence` = `NA`) are left out: their label says only that the
species was heard somewhere in the recording.

The table of copied clips is also written to `training_set.csv` in
`output_dir`; keep it with the classifier, to leave these clips out of
later validation rounds with
[`exclude_training_clips()`](https://provetelab.org/sheepdog/reference/exclude_training_clips.md).
