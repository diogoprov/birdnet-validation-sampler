# Clipes revisados simulados: arquivos vazios em Positive/Negative
revisao_simulada <- function(d) {
  val <- read_validation_tables(list.files(
    system.file("extdata", "example", "validation", package = "sheepdog"),
    full.names = TRUE))
  dest <- file.path(d, "review", val$species_folder,
                    ifelse(val$verdict == "positive", "Positive", "Negative"))
  for (x in unique(dest)) dir.create(x, recursive = TRUE)
  file.create(file.path(dest, val$clip_file))
  suppressMessages(classify_review(
    dplyr::select(val, -verdict, -reviewed_path), file.path(d, "review")))
}

test_that("read_validation_tables() stacks every column and verdict", {
  f <- list.files(system.file("extdata", "example", "validation",
                              package = "sheepdog"), full.names = TRUE)
  val <- read_validation_tables(f)
  expect_true(all(c("verdict", "species_folder", "reviewed_path") %in%
                    names(val)))
  expect_type(val$night, "character")
  expect_identical(nrow(val), sum(vapply(f, \(x) nrow(read.csv(x)),
                                         integer(1))))
  expect_warning(read_validation_tables(c(f[1], "nao_existe.csv")),
                 "Not found")
})

test_that("build_training_set() builds the BirdNET layout", {
  d <- withr::local_tempdir()
  rev <- revisao_simulada(d)
  out <- file.path(d, "training")
  ts <- suppressWarnings(suppressMessages(
    build_training_set(rev, out, test_sites = "NHE")))
  expect_setequal(unique(ts$set), c("train", "test"))
  expect_true(all(ts$set[ts$site == "NHE"] == "test"))
  pastas <- list.dirs(file.path(out, "train"), recursive = FALSE,
                      full.names = FALSE)
  expect_true("-Boana raniceps_boa-ran" %in% pastas)
  expect_true("Boana raniceps_boa-ran" %in% pastas)
  n_pos <- length(list.files(file.path(out, "train",
                                       "Boana raniceps_boa-ran")))
  expect_identical(n_pos, sum(ts$set == "train" & ts$verdict == "positive" &
                                ts$species_code == "Boana raniceps_boa-ran"))
  expect_true(file.exists(file.path(out, "training_set.csv")))
  # classes com poucos arquivos avisam
  expect_warning(suppressMessages(
    build_training_set(rev, file.path(d, "t2"), min_files = 1e6)),
    "fewer than")
  # sem negativos
  ts2 <- suppressWarnings(suppressMessages(
    build_training_set(rev, file.path(d, "t3"), negatives = FALSE)))
  expect_true(all(ts2$verdict == "positive"))
})

test_that("exclude_training_clips() drops overlapping clips", {
  man <- tibble::tibble(
    species_code = c("a", "a", "a", "b"),
    source_audio = c("x.wav", "x.wav", "y.wav", "x.wav"),
    clip_start = c(0, 6, 0, 0), clip_end = c(3, 9, 3, 3))
  treino <- tibble::tibble(species_code = "a", source_audio = "x.wav",
                           clip_start = 1.5, clip_end = 4.5)
  out <- suppressMessages(exclude_training_clips(man, treino))
  # so o 1o clipe se sobrepoe (mesma especie, mesma gravacao)
  expect_identical(nrow(out), 3L)
  expect_false(any(out$species_code == "a" & out$source_audio == "x.wav" &
                     out$clip_start == 0))
})

test_that("training copies omit unlocalised recordings and keep provenance", {
  d <- withr::local_tempdir()
  reviewed <- file.path(d, c("good.wav", "whole.wav"))
  file.create(reviewed)
  v <- tibble::tibble(site = "A", species_code = "sp", clip_file = basename(reviewed),
                      verdict = "positive", reviewed_path = reviewed,
                      confidence = c(.9, NA_real_))
  expect_message(out <- build_training_set(
    v, file.path(d, "train"), min_files = 1), "whole-recording")
  expect_identical(out$clip_file, "good.wav")
  expect_true(all(is.na(out$source_audio)))
  expect_equal(readr::read_csv(file.path(d, "train", "training_set.csv"),
                               show_col_types = FALSE)$clip_file, "good.wav")
  expect_error(build_training_set(v[v$confidence %in% NA_real_, ],
                   file.path(d, "empty")), "No reviewed clip")
  expect_error(build_training_set(v[c("site", "verdict")], d), "lacks the column")
})

test_that("missing training clips warn without claiming successful copies", {
  d <- withr::local_tempdir()
  v <- tibble::tibble(site = "A", species_code = "sp", clip_file = "missing.wav",
                      verdict = "positive", reviewed_path = file.path(d, "missing.wav"))
  expect_warning(out <- suppressMessages(build_training_set(v, file.path(d, "out"),
                         min_files = 0)), "could not be copied")
  expect_equal(nrow(out), 0L)
})

test_that("training exclusion handles missing provenance and touching intervals", {
  man <- tibble::tibble(species_code = "sp", source_audio = "same.wav",
                        clip_start = c(0, 3, 6), clip_end = c(3, 6, 9))
  ts <- tibble::tibble(species_code = "sp", source_audio = "same.wav",
                       clip_start = 3, clip_end = 6)
  d <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(ts, d)
  out <- suppressMessages(exclude_training_clips(man, d))
  expect_equal(out$clip_start, c(0, 6))
  ts$clip_start <- NA_real_
  expect_warning(kept <- exclude_training_clips(man, ts), "nothing excluded")
  expect_identical(kept, man)
  ts$clip_start <- 20; ts$clip_end <- 23
  expect_identical(suppressMessages(exclude_training_clips(man, ts)), man)
  expect_error(read_validation_tables(character()), "No validation table")
})
