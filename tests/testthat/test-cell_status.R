test_that("cell_status() separates reliable, absent and unreliable cells", {
  skip_if_not_installed("lme4")
  ex <- system.file("extdata", "example", "validation", package = "sheepdog")
  val <- suppressMessages(read_validations(list.files(ex, full.names = TRUE)))
  # o m4 e singular nestes dados; o aviso nao interessa aqui
  fit <- suppressWarnings(fit_calibration(
    val, calibration_models()$m4_species_x_site))
  st <- cell_status(fit, val, p_min = 0.95, min_n = 15)
  expect_identical(nrow(st), 8L * 4L)
  expect_true(all(st$status %in% c("reliable", "probably_absent",
                                   "unreliable")))
  # pse-pla e a especie dificil do exemplo: nunca chega a 0.95
  expect_true(all(st$status[st$species == "pse_pla"] != "reliable"))
  # celulas confiaveis tem limiar dentro da faixa revisada
  rel <- st[st$status == "reliable", ]
  expect_true(all(rel$threshold <= rel$max_confidence))
  # celulas sem TP revisado = provavelmente ausentes
  expect_true(all(st$status[st$n_tp == 0 & st$n_reviewed > 0] ==
                    "probably_absent"))
  core <- suggest_core_species(st)
  expect_false("pse_pla" %in% core)
  expect_true(all(c("boa_ran", "phy_cuv") %in% core))
})

test_that("suggest_core_species() needs no unreliable cell", {
  st <- tibble::tibble(
    species = c("a", "a", "b", "b", "c", "c"),
    status = c("reliable", "probably_absent", "reliable", "unreliable",
               "probably_absent", "probably_absent"))
  expect_identical(suggest_core_species(st), "a")
})

test_that("cell_status() includes extreme endpoints without extrapolation", {
  fit <- structure(list(), sheepdog_levels = list(site = "A", species = "sp"))
  seen <- NULL
  local_mocked_bindings(predict_tp = function(modelo, dados) {
    seen <<- dados$confidence
    dados$confidence
  })
  validations <- function(scores) tibble::tibble(
    site = factor("A"), species = factor("sp"),
    confidence = scores, tp = rep(1L, length(scores)))

  # A crossing above .99 used to be missed even though the maximum
  # reviewed score reached it (the Curiango regression).
  st <- cell_status(fit, validations(seq(.991, .9998, length.out = 20)),
                    p_min = .995)
  expect_identical(st$status, "reliable")
  expect_equal(st$threshold, .9998)
  expect_true(all(seen >= .991 & seen <= .9998))
  expect_true(all(c(.991, .9998) %in% seen))

  # Rounding the lower endpoint down used to report an unreviewed score.
  st <- cell_status(fit, validations(seq(.123, .127, length.out = 20)),
                    p_min = .12)
  expect_equal(st$threshold, .123)
  expect_true(all(seen >= .123 & seen <= .127))

  st <- cell_status(fit, validations(rep(.9998, 20)), p_min = .995)
  expect_equal(st$threshold, .9998)
  expect_equal(seen, .9998)

  st <- cell_status(fit, validations(rep(.994, 20)), p_min = .995)
  expect_identical(st$status, "unreliable")
  expect_true(is.na(st$threshold))
})
