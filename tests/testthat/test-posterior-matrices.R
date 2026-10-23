test_that("posterior matrix intervals preserve each draw and known uncertainty", {
  # Draw 1 detects species a on one of two nights; draw 2 detects it on
  # both. Species b is never detected. Frequencies are therefore .5/1
  # for a and 0/0 for b, independently of rows' ordering.
  h <- tidyr::expand_grid(draw = c(11L, 29L), site = "A",
                          species = c("a", "b"), night = c("20240101", "20240102")) |>
    dplyr::mutate(detection = as.integer(species == "a" &
                  (draw == 29L | night == "20240101")),
                  detection_k1 = detection, detection_k2 = detection,
                  detection_k3 = detection)
  out <- community_matrices_draws(h[nrow(h):1, ], c("a", "b"),
                                  k_min = 1, min_nights_month = 2,
                                  probs = c(.25, .75))
  a <- out$summary[out$summary$species == "a", ]
  b <- out$summary[out$summary$species == "b", ]
  expect_equal(a$frequency_mean, .75)
  expect_equal(a$frequency_lower, .625)
  expect_equal(a$frequency_upper, .875)
  expect_equal(b$frequency_mean, 0)
  expect_equal(b$frequency_lower, 0)
  expect_equal(b$frequency_upper, 0)
  expect_setequal(out$draws$draw, c(11L, 29L))
  expect_equal(sort(out$draws$frequency[out$draws$species == "a"]), c(.5, 1))
  expect_true(all(out$summary$n_nights_recorded == 2L))
})

test_that("posterior reliability uses draw probability rather than only the mean", {
  # Equal mean, different posterior support for exceeding p_min.
  d <- cbind(c(.80, .80, 1, 1), rep(.90, 4))
  s <- sheepdog:::summarise_grid_draws(d, p_min = .95, lower_prob = .25)
  expect_equal(s$p_tp, c(.9, .9))
  expect_equal(s$pr_reliable, c(.5, 0))
  expect_equal(s$p_tp_lower, c(.8, .9))
  expect_error(history_draws(list(), data.frame()), "engine.*brms")
  expect_error(calibration_diagnostics(list()), "engine.*brms")
})
