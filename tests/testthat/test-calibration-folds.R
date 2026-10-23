fold_fixture <- function() {
  d <- expand.grid(site = c("A", "B"), species = c("a", "b"),
                   recording = sprintf("r%02d", 1:10), clip = 1:4,
                   KEEP.OUT.ATTRS = FALSE)
  d$site <- factor(d$site)
  d$species <- factor(d$species)
  d$night <- rep(sprintf("n%02d", 1:5), length.out = nrow(d))
  d$confidence <- rep(c(.2, .4, .6, .8), length.out = nrow(d))
  d$logit_conf <- qlogis(d$confidence)
  d$tp <- rep(c(0L, 1L), length.out = nrow(d))
  d
}

test_that("clip folds reproduce the legacy assignment and restore random state", {
  d <- fold_fixture()
  old <- withr::with_seed(2026, d |>
    dplyr::group_by(site, species) |>
    dplyr::mutate(fold = sample(rep_len(seq_len(5), dplyr::n()))) |>
    dplyr::ungroup())
  withr::local_seed(99)
  before <- .Random.seed
  expect_identical(calibration_folds(d), old$fold)
  expect_identical(.Random.seed, before)
})

test_that("recording and night groups stay intact across species", {
  d <- fold_fixture()
  for (group in c("recording", "night")) {
    withr::local_seed(99)
    before <- .Random.seed
    f <- calibration_folds(d, fold_group = group)
    expect_identical(.Random.seed, before)
    expect_identical(f, calibration_folds(d, fold_group = group))
    expect_setequal(f, 1:5)
    key <- interaction(d$site, d[[group]], drop = TRUE)
    expect_true(all(vapply(split(f, key), function(x) length(unique(x)) == 1L,
                           logical(1))))
    expect_identical(f, calibration_folds(d, fold_group = c("site", group)))
    # Ordering input rows does not alter a group's assignment.
    order <- rev(seq_len(nrow(d)))
    expect_identical(f[order], calibration_folds(d[order, ], fold_group = group))
    groups <- unique(data.frame(site = d$site, key = key, fold = f))
    for (site in levels(d$site)) {
      n <- table(factor(groups$fold[groups$site == site], levels = 1:5))
      expect_true(max(n) - min(n) <= 1)
    }
  }
})

test_that("grouped folds reject missing IDs and insufficient groups", {
  d <- fold_fixture()
  expect_error(calibration_folds(d, fold_group = "missing"), "Missing.*columns")
  expect_error(calibration_folds(d, fold_group = character()), "character vector")
  expect_error(calibration_folds(d, fold_group = "species"), "not species")
  expect_error(calibration_folds(d, fold_group = "tp"), "not species")
  d$recording <- as.character(d$recording)
  d$recording[1] <- NA
  expect_error(calibration_folds(d, fold_group = "recording"), "missing or empty")
  d$recording[1] <- " "
  expect_error(calibration_folds(d, fold_group = "recording"), "missing or empty")
  d <- fold_fixture()
  d$night <- "one"
  expect_error(calibration_folds(d, fold_group = "night"), "too few at: A, B")
  for (k in list(1, 2.5, NA_real_, Inf, c(2, 3))) {
    expect_error(calibration_folds(d, k_folds = k), "integer of at least two")
  }
})

test_that("the model comparison uses grouped splits for every candidate", {
  d <- fold_fixture()
  calls <- list()
  local_mocked_bindings(
    fit_model = function(formula, dados) {
      calls[[length(calls) + 1L]] <<- dados
      list()
    },
    predict_tp = function(modelo, dados) rep(.5, nrow(dados)))
  cv <- suppressMessages(compare_calibration_models(d,
    models = list(a = tp ~ logit_conf, b = tp ~ 1), fold_group = "recording"))
  f <- calibration_folds(d, fold_group = "recording")
  expect_length(calls, 10)
  for (i in seq_along(calls)) {
    k <- (i - 1L) %% 5L + 1L
    train <- paste(calls[[i]]$site, calls[[i]]$recording)
    test <- paste(d$site[f == k], d$recording[f == k])
    expect_false(any(train %in% test))
    expect_equal(nrow(calls[[i]]), sum(f != k))
  }
  expect_true(all(cv$n_failed == 0L))
  expect_true(all(is.finite(cv$logloss_mean)))
})

test_that("single-verdict test folds keep probability scores without failed fits", {
  d <- fold_fixture()
  # Whole nights have one verdict each. Probability scores remain
  # defined even though the ROC curve does not.
  d$tp <- as.integer(calibration_folds(d, k_folds = 2,
                                      fold_group = "night") == 2L)
  local_mocked_bindings(
    fit_model = function(...) list(),
    predict_tp = function(modelo, dados) rep(.5, nrow(dados)))
  cv <- suppressMessages(compare_calibration_models(d,
    models = list(global = tp ~ 1), k_folds = 2, fold_group = "night"))
  expect_true(is.na(cv$auc_mean))
  expect_identical(cv$n_failed, 0L)
  expect_equal(cv$logloss_mean, log(2))
  expect_equal(cv$brier_mean, .25)
  expect_identical(select_calibration_model(cv, "one_se_logloss", 2), "global")
  expect_error(select_calibration_model(cv, "best_auc", 2), "No finite AUC")
  cv$logloss_mean <- NaN
  expect_error(select_calibration_model(cv), "No finite log-loss")
})

test_that("validation metadata is retained only on request", {
  path <- tempfile(fileext = ".csv")
  withr::defer(unlink(path))
  d <- tibble::tibble(site = "A", species_folder = "sp", confidence = .8,
                      verdict = "positive", source_audio = "audio.wav", night = "20260101")
  readr::write_csv(d, path)
  legacy <- suppressMessages(read_validations(path))
  expect_named(legacy, c("site", "species", "confidence", "logit_conf", "tp"))
  kept <- suppressMessages(read_validations(path, keep = c("source_audio", "night")))
  expect_identical(kept$source_audio, "audio.wav")
  expect_equal(kept$night, 20260101)
  expect_identical(kept[names(legacy)], legacy)
  expect_error(read_validations(path, keep = "missing"), "Missing columns.*keep")
  expect_error(read_validations(path, keep = TRUE), "character vector")
})

test_that("calibrate() carries grouping metadata through to an audit file", {
  path <- tempfile(fileext = ".csv")
  withr::defer(unlink(path))
  d <- fold_fixture()
  d$source_audio <- as.character(d$recording)
  d$species_folder <- as.character(d$species)
  d$verdict <- ifelse(d$tp == 1, "positive", "negative")
  readr::write_csv(d, path)
  seen <- NULL
  local_mocked_bindings(
    compare_calibration_models = function(validations, models, k_folds, seed,
                                          fold_group) {
      seen <<- list(data = validations, group = fold_group)
      tibble::tibble(model = "m0_global", logloss_mean = .3, logloss_sd = .01,
                     prop_singular = 0, complexity = 1L)
    },
    fit_calibration = function(...) stop("stopped after audit"))
  out <- withr::local_tempdir()
  expect_error(suppressMessages(calibrate(path, NULL, out,
                        fold_group = "source_audio")), "stopped after audit")
  expect_identical(seen$group, "source_audio")
  expect_identical(seen$data$source_audio, d$source_audio)
  audit <- readr::read_csv(file.path(out, "calibration_folds.csv"),
                            show_col_types = FALSE)
  expect_equal(audit$validation_row, seq_len(nrow(d)))
  expect_equal(audit$fold, calibration_folds(seen$data, fold_group = "source_audio"))
  expect_true(all(vapply(split(audit$fold, interaction(audit$site,
                        audit$source_audio)), function(x) length(unique(x)) == 1,
                        logical(1))))
})
