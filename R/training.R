#' Read and stack the validation tables
#'
#' Stacks the `validation_by_clip.csv` tables of several runs or sites
#' (output of [post_validation()]) and keeps every column and every
#' verdict, unlike [read_validations()], which keeps only what the
#' calibration needs. Tables written by v1.2.0 (`validacao_por_clipe.csv`)
#' are also read.
#'
#' @param files Paths to the `validation_by_clip.csv` files. Missing files
#'   are skipped with a warning.
#'
#' @return A tibble with the columns of the validation tables; `night` and
#'   `recording_date` are character.
#' @export
read_validation_tables <- function(files) {
  tabs <- map(files, function(f) {
    if (!file.exists(f)) { warning("Not found: ", f); return(NULL) }
    read_manifest(f) |>
      mutate(across(any_of(c("night", "recording_date")), as.character))
  })
  out <- list_rbind(tabs)
  if (is.null(out) || nrow(out) == 0) stop("No validation table read.")
  out
}

#' Build the training folders for BirdNET-Analyzer
#'
#' Copies the reviewed clips into the folder layout that the training
#' script of BirdNET-Analyzer expects: one folder per class, named after
#' the label (`species_code`, so the retrained classifier keeps the labels
#' of the current one), with the negatives of a class in a folder with the
#' same name prefixed by `-`. Clips of the sites in `test_sites` go to a
#' separate `test` folder, to be passed as `--test_data`, so that the new
#' classifier is evaluated on sites it was not trained on.
#'
#' The layout follows the documentation of BirdNET-Analyzer (version
#' 2.4.0, `birdnet_analyzer.train`), which also recommends at least 100
#' files per species; classes below `min_files` in the training set raise
#' a warning. Whole-recording clips of `"random_recordings"` (longer than
#' 3 s, `confidence` = `NA`) are left out: their label says only that the
#' species was heard somewhere in the recording.
#'
#' The table of copied clips is also written to `training_set.csv` in
#' `output_dir`; keep it with the classifier, to leave these clips out of
#' later validation rounds with [exclude_training_clips()].
#'
#' @param validation Reviewed clips, as returned by [classify_review()],
#'   [post_validation()] (`$validation`) or [read_validation_tables()]. It
#'   needs `site`, `species_code`, `clip_file`, `verdict` and
#'   `reviewed_path` (the path where the review left each clip).
#' @param output_dir Output folder; `train/` and, with `test_sites`,
#'   `test/` are created in it.
#' @param test_sites Sites held out for testing. `NULL` puts every clip in
#'   `train/`.
#' @param negatives Copy the negative clips into `-<species_code>` folders.
#' @param min_files Minimum number of positive training files per class
#'   below which a warning is raised.
#'
#' @return A tibble with one row per copied clip: `site`, `species_code`,
#'   `verdict`, `set` (`"train"` or `"test"`), `class_folder`, `clip_file`,
#'   `source_audio`, `clip_start`, `clip_end`, `from` and `to`, invisibly.
#' @export
build_training_set <- function(validation, output_dir, test_sites = NULL,
                               negatives = TRUE, min_files = 100) {
  faltam <- setdiff(c("site", "species_code", "clip_file", "verdict",
                      "reviewed_path"), names(validation))
  if (length(faltam) > 0) {
    stop("`validation` lacks the column(s): ", paste(faltam, collapse = ", "))
  }
  vereditos <- c("positive", if (negatives) "negative")
  clipes <- validation |>
    filter(verdict %in% vereditos, !is.na(reviewed_path))
  if ("confidence" %in% names(clipes)) {
    inteiras <- sum(is.na(clipes$confidence))
    if (inteiras > 0) {
      message(inteiras, " whole-recording clip(s) (no confidence) left out.")
      clipes <- filter(clipes, !is.na(confidence))
    }
  }
  if (nrow(clipes) == 0) stop("No reviewed clip to copy.")
  desconhecidos <- setdiff(test_sites, unique(clipes$site))
  if (length(desconhecidos) > 0) {
    warning("Site(s) in `test_sites` without clips: ",
            paste(desconhecidos, collapse = ", "))
  }

  for (col in c("source_audio", "clip_start", "clip_end")) {
    if (!col %in% names(clipes)) clipes[[col]] <- NA
  }
  copia <- clipes |>
    transmute(site, species_code, verdict,
              set = if_else(site %in% test_sites, "test", "train"),
              class_folder = paste0(if_else(verdict == "negative", "-", ""),
                                    species_code),
              clip_file, source_audio, clip_start, clip_end,
              from = reviewed_path,
              to = file.path(output_dir, set, class_folder, clip_file))

  walk(unique(dirname(copia$to)), dir.create, recursive = TRUE,
       showWarnings = FALSE)
  ok <- file.copy(copia$from, copia$to, overwrite = TRUE)
  if (!all(ok)) {
    warning(sum(!ok), " clip(s) could not be copied - check `reviewed_path`.")
  }
  copia <- copia[ok, ]

  poucos <- copia |>
    filter(set == "train", verdict == "positive") |>
    count(species_code) |>
    right_join(distinct(copia, species_code), by = "species_code") |>
    mutate(n = replace_na(n, 0L)) |>
    filter(n < min_files)
  if (nrow(poucos) > 0) {
    warning("Class(es) with fewer than ", min_files, " positive training ",
            "files: ", paste0(poucos$species_code, " (", poucos$n, ")",
                              collapse = ", "), call. = FALSE)
  }

  write_csv(copia, file.path(output_dir, "training_set.csv"))
  message(nrow(copia), " clips copied to ", output_dir, " (",
          sum(copia$set == "train"), " train, ", sum(copia$set == "test"),
          " test).")
  invisible(copia)
}

#' Leave the training clips out of a manifest
#'
#' Drops from a clip manifest the clips that overlap, for the same species
#' and the same recording, a clip used to train the classifier (the
#' `training_set.csv` written by [build_training_set()]). Use it before
#' reviewing the detections of a retrained classifier: scores of the
#' clips it was trained on are biased upwards.
#'
#' @param manifest Clip manifest, as returned by [select_clips()] or read
#'   from `clip_manifest.csv`.
#' @param training_set Table returned by [build_training_set()], or the
#'   path to its `training_set.csv`.
#'
#' @return The manifest without the overlapping clips.
#' @export
exclude_training_clips <- function(manifest, training_set) {
  if (is.character(training_set)) {
    training_set <- read_csv(training_set, show_col_types = FALSE)
  }
  treino <- training_set |>
    filter(!is.na(source_audio), !is.na(clip_start)) |>
    distinct(species_code, source_audio, t_ini = clip_start,
             t_fim = clip_end)
  if (nrow(treino) == 0) {
    warning("`training_set` has no source_audio/clip_start; nothing excluded.")
    return(manifest)
  }
  sobrepoe <- manifest |>
    mutate(.linha = row_number()) |>
    inner_join(treino, by = c("species_code", "source_audio"),
               relationship = "many-to-many") |>
    filter(clip_start < t_fim, clip_end > t_ini) |>
    pull(.linha) |>
    unique()
  message(length(sobrepoe), " clip(s) used in training left out of the ",
          "manifest.")
  if (length(sobrepoe) == 0) return(manifest)
  manifest[-sobrepoe, ]
}
