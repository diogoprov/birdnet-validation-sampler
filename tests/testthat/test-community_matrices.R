nucleo <- c("boa_ran", "den_nan", "sci_nas", "xxx_aus")

for (k in 1:2) {
  test_that(paste0("build_community_matrices() reproduces v1.2.0: k = ", k), {
    saida <- withr::local_tempdir()
    expect_warning(suppressMessages(build_community_matrices(
      ref_path("mat", "historico_simulado.csv"), saida,
      core_species = nucleo, k_min = k)), "xxx_aus")
    pares <- c(paste0("frequency_matrix_site_month_k", k, ".csv"),
               paste0("matriz_frequencia_local_mes_k", k, ".csv"),
               paste0("count_matrix_site_month_k", k, ".csv"),
               paste0("matriz_contagens_local_mes_k", k, ".csv"),
               "effort_site_month.csv", "esforco_local_mes.csv")
    for (i in seq(1, length(pares), by = 2)) {
      expect_identical(read_as_text(file.path(saida, pares[i])),
                       ref_table(paste0("mat_k", k), pares[i + 1]),
                       label = pares[i])
    }
  })
}

test_that("community_matrices() takes the history of detection_history()", {
  h <- tibble::tibble(
    site = "S", species = rep(c("a", "b"), each = 6),
    night = rep(sprintf("202201%02d", 1:6), 2),
    detection_k1 = c(1, 1, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1),
    detection_k2 = c(1, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0))
  m <- community_matrices(h, c("a", "b"), k_min = 2, min_nights_month = 5)
  expect_identical(m$frequency$a, 1 / 6)
  expect_identical(m$frequency$b, 3 / 6)
  expect_identical(m$counts$b, 3L)
  expect_true(m$effort$included)
  expect_error(community_matrices(h, "a", k_min = 3), "detection_k3")
})

test_that("build_community_matrices() reads a new-format history file", {
  antigo <- readr::read_csv(ref_path("mat", "historico_simulado.csv"),
                            col_types = readr::cols(noite = "c"))
  novo <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(sheepdog:::from_legacy(antigo), novo)
  expect_true("night" %in% names(readr::read_csv(novo, n_max = 0,
                                                 show_col_types = FALSE)))
  saida <- withr::local_tempdir()
  m <- suppressMessages(build_community_matrices(
    novo, saida, core_species = nucleo[1:3], k_min = 3, min_nights_month = 10))
  expect_identical(names(m$frequency),
                   c("site", "month", "n_nights_recorded", nucleo[1:3]))
  expect_true(all(m$effort$n_nights_recorded[m$effort$included] >= 10))
  expect_true(any(!m$effort$included))
  expect_false(any(paste(m$frequency$site, m$frequency$month) %in%
                     paste(m$effort$site, m$effort$month)[!m$effort$included]))
  expect_identical(names(read_as_text(file.path(
    saida, "effort_site_month.csv"))),
    c("site", "month", "n_nights_recorded", "included"))
  expect_error(community_matrices(antigo, character()), "empty")
})
