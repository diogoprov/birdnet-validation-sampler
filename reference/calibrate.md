# Calibrate confidence scores and build detection histories

Runs the whole calibration stage: reads the reviewed clips, compares the
candidate models by cross-validation, refits the best one to all the
clips, optionally draws the effort curve, scores every detection of the
complete selection tables and builds the nightly detection history.
Writes to `output_dir`:

- `model_comparison.csv`
  ([`compare_calibration_models()`](https://provetelab.org/sheepdog/reference/compare_calibration_models.md));

- `calibration_model.rds` and `calibration_model.txt` (the refitted best
  model and its summary);

- `calibration_curves.png`
  ([`plot_calibration()`](https://provetelab.org/sheepdog/reference/plot_calibration.md)),
  when 'ggplot2' is installed;

- `effort_curve.csv`
  ([`calibration_effort()`](https://provetelab.org/sheepdog/reference/calibration_effort.md)),
  when `effort_curve` is `TRUE`;

- `calibrated_detections_<site>.csv`, one per site
  ([`score_detections()`](https://provetelab.org/sheepdog/reference/score_detections.md));

- `nightly_detection_history.csv`
  ([`detection_history()`](https://provetelab.org/sheepdog/reference/detection_history.md));

- `detection_summary.csv`
  ([`summarise_history()`](https://provetelab.org/sheepdog/reference/summarise_history.md)).

## Usage

``` r
calibrate(
  validation_files,
  prediction_tables,
  output_dir,
  site_map = NULL,
  min_confidence = 0.1,
  p_min = 0.95,
  min_detections_night = 1,
  dawn_hour = 12,
  k_folds = 5,
  effort_curve = FALSE,
  effort_n = c(5, 10, 15, 20, 25, 30),
  effort_reps = 50,
  seed = 2026
)
```

## Arguments

- validation_files:

  Paths to the `validation_by_clip.csv` files of the sites (v1.2.0
  `validacao_por_clipe.csv` files are also read).

- prediction_tables:

  Named character vector of the complete selection tables, named by
  site.

- output_dir:

  Output folder; created if needed. The calibrated detections of a large
  project can take hundreds of MB.

- site_map:

  Optional named character vector to fix diverging site names, as
  `c(old = "new")`, e.g. `c(BEP2 = "BEP")`.

- min_confidence:

  Detections below this confidence are not scored.

- p_min:

  Threshold on the calibrated probability (not on the confidence score).

- min_detections_night:

  Repetition rule: minimum number of reliable detections for a night
  with detection.

- dawn_hour:

  Recordings that start before this hour belong to the night before.

- k_folds:

  Number of folds.

- effort_curve:

  Draw the effort curve (slow).

- effort_n, effort_reps:

  Training sizes and repetitions of the effort curve.

- seed:

  Seed of the fold assignment. The global random number generator is
  left as it was.

## Value

A list with `comparison`, `fit`, `effort` (or `NULL`), `scored` and
`history`, invisibly.

## Details

Converting BirdNET confidence scores into probabilities is recommended
by the BirdNET authors (Wood & Kahl 2024,
[doi:10.1007/s10336-024-02144-5](https://doi.org/10.1007/s10336-024-02144-5)
); calibration by logistic regression on logit(score) is applied, for
instance, by Owens et al. (2026,
[doi:10.64898/2026.06.01.729442](https://doi.org/10.64898/2026.06.01.729442)
). This function extends that approach with a hierarchical multi-species
structure. This is the function form of the v1.2.0 script
`calibracao.R`.
