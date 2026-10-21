# Package index

## Stage 1 - Validation data

Read BirdNET selection tables, select clips for manual review, and cut
and pack them.

- [`extract_validation_clips()`](https://provetelab.org/sheepdog/reference/extract_validation_clips.md)
  : Build the validation clip set
- [`read_selection_tables()`](https://provetelab.org/sheepdog/reference/read_selection_tables.md)
  : Read BirdNET selection tables
- [`select_clips()`](https://provetelab.org/sheepdog/reference/select_clips.md)
  : Select the clips to validate
- [`cut_clips()`](https://provetelab.org/sheepdog/reference/cut_clips.md)
  : Cut the selected clips
- [`pack_clips()`](https://provetelab.org/sheepdog/reference/pack_clips.md)
  : Pack the clips into one zip per species

## Stage 1 - After the review

Classify the reviewed clips and summarise precision, thresholds,
presence and retraining clips.

- [`post_validation()`](https://provetelab.org/sheepdog/reference/post_validation.md)
  : Summarise the manual validation
- [`classify_review()`](https://provetelab.org/sheepdog/reference/classify_review.md)
  : Classify the reviewed clips
- [`precision_by_bin()`](https://provetelab.org/sheepdog/reference/precision_by_bin.md)
  : Precision by confidence bin
- [`suggest_thresholds()`](https://provetelab.org/sheepdog/reference/suggest_thresholds.md)
  : Suggest a confidence threshold per species
- [`nightly_presence()`](https://provetelab.org/sheepdog/reference/nightly_presence.md)
  : Confirmed presence by night
- [`retraining_clips()`](https://provetelab.org/sheepdog/reference/retraining_clips.md)
  : Positive clips for retraining
- [`plot_precision()`](https://provetelab.org/sheepdog/reference/plot_precision.md)
  : Plot the precision curves

## Stage 2 - Calibration

Calibrate confidence scores into probabilities of true detection and
build nightly detection histories.

- [`calibrate()`](https://provetelab.org/sheepdog/reference/calibrate.md)
  : Calibrate confidence scores and build detection histories
- [`read_validations()`](https://provetelab.org/sheepdog/reference/read_validations.md)
  : Read the validation tables for calibration
- [`calibration_models()`](https://provetelab.org/sheepdog/reference/calibration_models.md)
  : Candidate calibration models
- [`compare_calibration_models()`](https://provetelab.org/sheepdog/reference/compare_calibration_models.md)
  : Compare calibration models by cross-validation
- [`fit_calibration()`](https://provetelab.org/sheepdog/reference/fit_calibration.md)
  : Fit the calibration model
- [`calibration_effort()`](https://provetelab.org/sheepdog/reference/calibration_effort.md)
  : Effort curve of the calibration
- [`score_detections()`](https://provetelab.org/sheepdog/reference/score_detections.md)
  : Score every detection with the calibration model
- [`detection_history()`](https://provetelab.org/sheepdog/reference/detection_history.md)
  : Nightly detection history
- [`summarise_history()`](https://provetelab.org/sheepdog/reference/summarise_history.md)
  : Summarise the detection history by site and species
- [`plot_calibration()`](https://provetelab.org/sheepdog/reference/plot_calibration.md)
  : Plot the calibration curves

## Stage 3 - Community matrices

Effort-standardised site x month matrices from calibrated histories.

- [`build_community_matrices()`](https://provetelab.org/sheepdog/reference/build_community_matrices.md)
  : Write the community matrices
- [`community_matrices()`](https://provetelab.org/sheepdog/reference/community_matrices.md)
  : Community matrices from the detection history

## Package

- [`sheepdog`](https://provetelab.org/sheepdog/reference/sheepdog-package.md)
  [`sheepdog-package`](https://provetelab.org/sheepdog/reference/sheepdog-package.md)
  : sheepdog: Sample, Validate and Calibrate 'BirdNET' Detections
