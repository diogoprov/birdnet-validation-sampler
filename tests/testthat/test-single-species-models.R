test_that("single-species candidates use site effects and keep the old family", {
  m <- calibration_models(single_species = TRUE)
  expect_named(m, c("m0_global", "m1_site_intercept", "m2_site_slope"))
  expect_true(all(vapply(m, function(f) !"species" %in% all.vars(f), logical(1))))
  u <- calibration_models(uncorrelated = TRUE, single_species = TRUE)
  expect_named(u, c(names(m), "m3_site_slope_uncorrelated"))
  expect_false(grepl("(logit_conf | site)", deparse1(u[[4]]), fixed = TRUE))
  expect_length(calibration_models(), 5)
  expect_length(calibration_models(TRUE), 6)
})

test_that("automatic candidates follow observed levels, not factor levels", {
  d <- data.frame(site = factor(rep(c("A", "B"), each = 50)),
    species = factor("one", levels = c("one", "unused")),
    logit_conf = rep(seq(-2, 2, length.out = 50), 2),
    tp = rep(c(0L, 1L, 1L, 0L, 1L), 20))
  expect_named(calibration_candidates(d), names(calibration_models(single_species = TRUE)))
  one <- d[d$site == "A", ]
  expect_named(calibration_candidates(one), "m0_global")
  expect_named(calibration_candidates(one, TRUE), "m0_global")
  # A global-only candidate set works even without lme4.
  cv <- suppressMessages(compare_calibration_models(one, k_folds = 2))
  expect_identical(cv$model, "m0_global")
  expect_identical(cv$n_failed, 0L)
  d$species <- factor(rep(c("one", "two"), 50))
  expect_named(calibration_candidates(d), names(calibration_models()))
  expect_named(calibration_candidates(d[d$site == "A", ]),
                names(calibration_models())[1:3])
})

test_that("the comparison and wrapper automatically use single-species candidates", {
  skip_if_not_installed("lme4")
  d <- withr::with_seed(7, {
    d <- expand.grid(site = c("A", "B", "C", "D"), night = 1:12,
                     clip = 1:4)
    d$species <- factor("sp")
    d$site <- factor(d$site)
    d$confidence <- runif(nrow(d), .1, .99)
    d$logit_conf <- qlogis(d$confidence)
    d$tp <- rbinom(nrow(d), 1, plogis(d$logit_conf +
                       c(A = -1, B = 0, C = .5, D = 1)[d$site]))
    d
  })
  auto <- suppressMessages(compare_calibration_models(d, k_folds = 3,
                                                       fold_group = "night"))
  explicit <- suppressMessages(compare_calibration_models(d,
    calibration_models(single_species = TRUE), k_folds = 3, fold_group = "night"))
  expect_equal(auto, explicit)
  expect_true(all(auto$n_failed == 0L))
  path <- tempfile(fileext = ".csv")
  withr::defer(unlink(path))
  d$species_folder <- "sp"
  d$verdict <- ifelse(d$tp == 1, "positive", "negative")
  readr::write_csv(d, path)
  chosen <- NULL
  local_mocked_bindings(fit_calibration = function(validations, formula, ...) {
    chosen <<- formula
    stop("stop after automatic selection")
  })
  out <- withr::local_tempdir()
  expect_error(suppressMessages(calibrate(path, NULL, out, k_folds = 3,
                 fold_group = "night")), "stop after automatic selection")
  expect_false("species" %in% all.vars(chosen))
  cmp <- readr::read_csv(file.path(out, "model_comparison.csv"), show_col_types = FALSE)
  expect_setequal(cmp$model, names(calibration_models(single_species = TRUE)))
})
