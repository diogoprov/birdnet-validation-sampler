# Retraining the classifier with validated clips

The manual review of stage 1 produces two kinds of labelled clips: clips
that contain the species (positives) and clips in which the classifier
detected the species but the reviewer did not hear it (negatives).
Besides measuring precision and feeding the calibration, both can be
used to retrain the BirdNET custom classifier. This article shows how to
turn the reviewed clips into a training data set in the layout that
BirdNET-Analyzer expects, how to keep an independent set for testing the
new classifier, and what has to be redone after retraining.

Training itself runs in BirdNET-Analyzer (Python), not in R. The
requirements quoted below come from the BirdNET-Analyzer documentation
(version 2.4.0, section `birdnet_analyzer.train` of the [command line
interface](https://birdnet-team.github.io/BirdNET-Analyzer/stable/usage/cli.html));
check the version you use, since the training options change between
releases.

``` r

library(sheepdog)
suppressPackageStartupMessages(library(dplyr))
ex <- system.file("extdata", "example", package = "sheepdog")
```

## What BirdNET-Analyzer expects

According to its documentation, the training script of BirdNET-Analyzer:

- takes a folder with **one subfolder per class**, and uses the folder
  names as labels. The recommended label format is
  `<scientific name>_<common name>`, although other formats work;
- accepts **negative samples** of a class in a folder with the same name
  prefixed by `-` (e.g. `-Boana raniceps_boa-ran`). Negative samples are
  used for training only, not for validation, and only when the folder
  with the positives of that class exists;
- treats a folder named `Noise`, `Background`, `Other` or `Silence` as a
  non-event class;
- resamples the audio to 48 kHz and works on 3 s segments;
- recommends at least 100 audio files per species, although training
  also works with fewer;
- accepts an independent test set (`--test_data`).

The documentation also states that custom classifiers trained with
BirdNET-Analyzer are licensed under CC BY-NC-SA 4.0.

The clips cut by sheepdog already fit this layout: they are 3 s segments
of the original recordings, and `species_code` keeps the full label of
the classifier (`<scientific name>_<code>`), which can be used as the
folder name so that the retrained classifier reports the same labels.

## The reviewed clips

We use the reviewed clips shipped with the package. In a real project
the review is done in the Review tab of the BirdNET GUI, which moves
each clip into a `Positive` or `Negative` subfolder; here we recreate
that folder structure with empty `.wav` files from the verdicts of the
example tables, and read it back with
[`classify_review()`](https://provetelab.org/sheepdog/reference/classify_review.md),
which records where each clip was found (`reviewed_path`).

``` r

validation <- list.files(file.path(ex, "validation"), full.names = TRUE) |>
  lapply(readr::read_csv, show_col_types = FALSE,
         col_types = readr::cols(night = "c", recording_date = "c")) |>
  bind_rows()

review_dir <- file.path(tempdir(), "review")
unlink(review_dir, recursive = TRUE)
dest <- file.path(review_dir, validation$species_folder,
                  ifelse(validation$verdict == "positive",
                         "Positive", "Negative"))
for (d in unique(dest)) dir.create(d, recursive = TRUE)
invisible(file.create(file.path(dest, validation$clip_file)))

reviewed <- validation |>
  select(-verdict, -reviewed_path) |>
  classify_review(review_dir) |>
  suppressMessages()
count(reviewed, species_code, verdict)
#> # A tibble: 16 × 3
#>    species_code                      verdict      n
#>    <chr>                             <chr>    <int>
#>  1 Boana raniceps_boa-ran            negative    88
#>  2 Boana raniceps_boa-ran            positive   232
#>  3 Dendropsophus nanus_den-nan       negative   161
#>  4 Dendropsophus nanus_den-nan       positive   159
#>  5 Elachistocleis bicolor_ela-bic    negative    34
#>  6 Elachistocleis bicolor_ela-bic    positive   286
#>  7 Leptodactylus fuscus_lep-fus      negative   151
#>  8 Leptodactylus fuscus_lep-fus      positive    98
#>  9 Leptodactylus podicipinus_lep-pod negative    43
#> 10 Leptodactylus podicipinus_lep-pod positive   255
#> 11 Physalaemus cuvieri_phy-cuv       negative    32
#> 12 Physalaemus cuvieri_phy-cuv       positive   288
#> 13 Pseudis platensis_pse-pla         negative   220
#> 14 Pseudis platensis_pse-pla         positive   100
#> 15 Scinax nasicus_sci-nas            negative   161
#> 16 Scinax nasicus_sci-nas            positive   159
```

[`retraining_clips()`](https://provetelab.org/sheepdog/reference/retraining_clips.md)
lists the positives; the negatives are the reviewed clips with
`verdict == "negative"`.

``` r

positives <- retraining_clips(reviewed)
negatives <- filter(reviewed, verdict == "negative")
```

## Keeping an independent test set

A retrained classifier has to be evaluated on clips that it did not see
during training. BirdNET-Analyzer holds out a validation split
(`--val_split`) drawn from the training folder itself, but clips from
the same site and night share background noise and calling individuals,
so a random split of clips tends to overstate performance (our
recommendation, not a statement of the BirdNET documentation). A
stricter test keeps whole sites (or whole nights) out of training and
passes them as `--test_data`.

Here we hold out one site:

``` r

test_site <- "NHE"
split_set <- function(df) {
  mutate(df, set = if_else(site == test_site, "test", "train"))
}
positives <- split_set(positives)
negatives <- split_set(negatives)
count(positives, set)
#> # A tibble: 2 × 2
#>   set       n
#>   <chr> <int>
#> 1 test    365
#> 2 train  1212
```

## Building the training folders

The function below copies the clips into the BirdNET layout: positives
in `<set>/<species_code>/` and negatives in `<set>/-<species_code>/`. In
a real project `reviewed_path` points to the clips where the review left
them.

``` r

copy_to_training <- function(clips, root, negative = FALSE) {
  prefix <- if (negative) "-" else ""
  to <- file.path(root, clips$set, paste0(prefix, clips$species_code))
  for (d in unique(to)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  ok <- file.copy(clips$reviewed_path, file.path(to, clips$clip_file))
  if (!all(ok)) warning(sum(!ok), " clip(s) not copied.")
  invisible(ok)
}

training_root <- file.path(tempdir(), "birdnet_training")
unlink(training_root, recursive = TRUE)
copy_to_training(positives, training_root)
copy_to_training(negatives, training_root, negative = TRUE)

list.files(file.path(training_root, "train"))
#>  [1] "-Boana raniceps_boa-ran"            "-Dendropsophus nanus_den-nan"      
#>  [3] "-Elachistocleis bicolor_ela-bic"    "-Leptodactylus fuscus_lep-fus"     
#>  [5] "-Leptodactylus podicipinus_lep-pod" "-Physalaemus cuvieri_phy-cuv"      
#>  [7] "-Pseudis platensis_pse-pla"         "-Scinax nasicus_sci-nas"           
#>  [9] "Boana raniceps_boa-ran"             "Dendropsophus nanus_den-nan"       
#> [11] "Elachistocleis bicolor_ela-bic"     "Leptodactylus fuscus_lep-fus"      
#> [13] "Leptodactylus podicipinus_lep-pod"  "Physalaemus cuvieri_phy-cuv"       
#> [15] "Pseudis platensis_pse-pla"          "Scinax nasicus_sci-nas"
```

How many files each class received, against the 100 files per species
recommended by the BirdNET documentation:

``` r

n_files <- tibble(
  folder = list.dirs(file.path(training_root, "train"),
                     recursive = FALSE, full.names = FALSE)) |>
  mutate(n = vapply(folder, function(f) length(list.files(
    file.path(training_root, "train", f))), integer(1)),
    below_100 = n < 100)
n_files
#> # A tibble: 16 × 3
#>    folder                                 n below_100
#>    <chr>                              <int> <lgl>    
#>  1 -Boana raniceps_boa-ran               43 TRUE     
#>  2 -Dendropsophus nanus_den-nan         122 FALSE    
#>  3 -Elachistocleis bicolor_ela-bic       18 TRUE     
#>  4 -Leptodactylus fuscus_lep-fus        121 FALSE    
#>  5 -Leptodactylus podicipinus_lep-pod    24 TRUE     
#>  6 -Physalaemus cuvieri_phy-cuv          23 TRUE     
#>  7 -Pseudis platensis_pse-pla           164 FALSE    
#>  8 -Scinax nasicus_sci-nas              100 FALSE    
#>  9 Boana raniceps_boa-ran               197 FALSE    
#> 10 Dendropsophus nanus_den-nan          118 FALSE    
#> 11 Elachistocleis bicolor_ela-bic       222 FALSE    
#> 12 Leptodactylus fuscus_lep-fus          48 TRUE     
#> 13 Leptodactylus podicipinus_lep-pod    194 FALSE    
#> 14 Physalaemus cuvieri_phy-cuv          217 FALSE    
#> 15 Pseudis platensis_pse-pla             76 TRUE     
#> 16 Scinax nasicus_sci-nas               140 FALSE
```

With the 2467 reviewed clips of the example, 2 of the 8 positive classes
have fewer than 100 training files. Classes with few positives are the
ones that most need clips from further review rounds before retraining.

## Which clips to add

Three points about the composition of the training set follow from how
the clips were chosen (our recommendations, not statements of the
BirdNET documentation):

- **Clips from the `"top"` design are the easy cases.** They are the
  highest-scoring detections, so they teach the classifier little about
  the calls it currently misses or scores low. Positives from the
  `"random_detections"` and `"random_recordings"` designs (see
  [`vignette("sampling-designs")`](https://provetelab.org/sheepdog/articles/sampling-designs.md))
  cover lower scores and calls the classifier did not detect.
- **Negatives with high scores are the most informative.** They are the
  sounds the classifier confuses with the species. Species with many
  high-scoring false positives in
  [`precision_by_bin()`](https://provetelab.org/sheepdog/reference/precision_by_bin.md)
  (see
  [`vignette("validation-effort")`](https://provetelab.org/sheepdog/articles/validation-effort.md))
  are the ones for which negatives matter most.
- **Whole-recording clips** of `"random_recordings"` are longer than
  3 s. BirdNET-Analyzer crops long files (`--crop_mode`), but the label
  of a whole recording says only that the species was heard somewhere in
  it. Cut the annotated calls into 3 s clips before using them as
  positives.

## Training

Training runs in a Python environment with BirdNET-Analyzer installed.
The commands below follow the example of the documentation (they are not
run here):

``` sh
python -m birdnet_analyzer.train birdnet_training/train \
  --test_data birdnet_training/test \
  -o checkpoints/custom/Custom_Classifier.tflite

python -m birdnet_analyzer.analyze recordings/ \
  --classifier checkpoints/custom/Custom_Classifier.tflite
```

Use `--model_format raven` (or `both`) if the classifier will also be
used in Raven. Hyperparameters such as `--hidden_units`,
`--learning_rate`, `--dropout` and the upsampling options affect the
result; the documentation recommends trying several settings, or
`--autotune`.

## After retraining

A retrained classifier produces new confidence scores, so everything
that was estimated from the scores of the old one no longer applies:

1.  Run the new classifier over the recordings to obtain new selection
    tables.
2.  Draw and review a new set of clips (stage 1). Do not reuse the clips
    used for training: their scores are biased upwards on the data the
    classifier was trained on.
3.  Recalibrate (stage 2,
    [`vignette("calibration")`](https://provetelab.org/sheepdog/articles/calibration.md))
    and rebuild the detection histories and community matrices (stage
    3).

Keeping track of which reviewed clips went into training (for example,
by saving the tables `positives` and `negatives` above with the
classifier version) makes it possible to exclude them from later
validation rounds.
