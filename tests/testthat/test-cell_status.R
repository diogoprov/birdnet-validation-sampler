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
