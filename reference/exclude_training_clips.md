# Leave the training clips out of a manifest

Drops from a clip manifest the clips that overlap, for the same species
and the same recording, a clip used to train the classifier (the
`training_set.csv` written by
[`build_training_set()`](https://provetelab.org/sheepdog/reference/build_training_set.md)).
Use it before reviewing the detections of a retrained classifier: scores
of the clips it was trained on are biased upwards.

## Usage

``` r
exclude_training_clips(manifest, training_set)
```

## Arguments

- manifest:

  Clip manifest, as returned by
  [`select_clips()`](https://provetelab.org/sheepdog/reference/select_clips.md)
  or read from `clip_manifest.csv`.

- training_set:

  Table returned by
  [`build_training_set()`](https://provetelab.org/sheepdog/reference/build_training_set.md),
  or the path to its `training_set.csv`.

## Value

The manifest without the overlapping clips.
