saidas_cal <- c(
  model_comparison.csv = "comparacao_modelos.csv",
  effort_curve.csv = "curva_esforco.csv",
  nightly_detection_history.csv = "historico_deteccao_noite.csv",
  detection_summary.csv = "resumo_deteccao_especie_local.csv",
  calibrated_detections_ARA.csv = "deteccoes_calibradas_ARA.csv",
  calibrated_detections_XAR.csv = "deteccoes_calibradas_XAR.csv",
  calibrated_detections_BAI.csv = "deteccoes_calibradas_BAI.csv"
)

# Mesmas entradas da referencia: validacoes no formato v1.2.0 (com o local
# XAR2 renomeado para XAR) e as tabelas de predicao simuladas
rodar_calibracao <- function(saida, ...) {
  raiz <- sim_root()
  suppressMessages(calibrate(
    validation_files = ref_path("cal", paste0("validacao_por_clipe_",
                                              c("ARA", "XAR2", "BAI"), ".csv")),
    prediction_tables = c(
      ARA = file.path(raiz, "tabelas/output_ARA/BirdNET_SelectionTable.txt"),
      XAR = file.path(raiz, "tabelas/output_XAR/BirdNET_SelectionTable.txt"),
      BAI = file.path(raiz, "tabelas/BAI/BirdNET_SelectionTable.txt")),
    output_dir = saida, site_map = c(XAR2 = "XAR"), ...))
}

test_that("calibrate() reproduces v1.2.0", {
  skip_if_not_installed("lme4")
  saida <- withr::local_tempdir()
  res <- rodar_calibracao(saida, effort_curve = TRUE, effort_n = c(5, 10),
                          effort_reps = 3)
  for (f in names(saidas_cal)) {
    ref <- ref_table("cal", saidas_cal[[f]])
    if (f == "model_comparison.csv") {
      ref$formula <- gsub("local", "site", gsub("especie", "species",
                                                ref$formula))
    }
    expect_same_table(read_as_text(file.path(saida, f)), ref, label = f)
  }
  expect_true(file.exists(file.path(saida, "calibration_model.rds")))
  expect_s4_class(res$fit, "glmerMod")
})

test_that("score_detections() needs a model from fit_calibration()", {
  fit <- stats::glm(tp ~ 1, family = stats::binomial,
                    data = data.frame(tp = c(0, 1)))
  expect_error(score_detections(c(A = "x.txt"), fit), "fit_calibration")
})

test_that("a global model scores without lme4-specific levels", {
  val <- suppressMessages(read_validations(
    ref_path("cal", paste0("validacao_por_clipe_", c("ARA", "XAR2", "BAI"),
                           ".csv")), site_map = c(XAR2 = "XAR")))
  expect_setequal(levels(val$site), c("ARA", "XAR", "BAI"))
  fit <- fit_calibration(val, calibration_models()$m0_global)
  sc <- suppressMessages(score_detections(
    c(ARA = file.path(sim_root(), "tabelas/output_ARA/BirdNET_SelectionTable.txt")),
    fit))
  expect_true(all(sc$p_tp > 0 & sc$p_tp < 1))
  expect_true(all(sc$confidence >= 0.1))
  # p_tp cresce com a confidence no modelo global
  expect_true(stats::cor(sc$confidence, sc$p_tp, method = "spearman") > 0.99)
})

test_that("calibration functions leave the global RNG untouched", {
  skip_if_not_installed("lme4")
  val <- suppressMessages(read_validations(
    ref_path("cal", "validacao_por_clipe_ARA.csv")))
  set.seed(1)
  antes <- .Random.seed
  suppressMessages(compare_calibration_models(
    val, calibration_models()["m0_global"], k_folds = 2))
  expect_identical(.Random.seed, antes)
})

test_that("read_validations() reads the new format like the v1.2.0 one", {
  antigo <- ref_path("cal", "validacao_por_clipe_ARA.csv")
  novo <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(sheepdog:::from_legacy(readr::read_csv(
    antigo, show_col_types = FALSE)), novo)
  expect_identical(suppressMessages(read_validations(novo)),
                   suppressMessages(read_validations(antigo)))
})

test_that("score_detections() assigns small hours to the night before", {
  val <- suppressMessages(read_validations(ref_path(
    "cal", "validacao_por_clipe_ARA.csv")))
  fit <- fit_calibration(val, calibration_models()$m0_global)
  d <- withr::local_tempdir()
  tab <- file.path(d, "t.txt")
  writeLines(c(
    "Species Code\tConfidence\tBegin Path\tFile Offset (s)",
    "Boana raniceps_boa-ran\t0.9\tA_20220110_013000.wav\t0",
    "Boana raniceps_boa-ran\t0.9\tA_20220110_193000.wav\t0",
    "Boana raniceps_boa-ran\t0.05\tA_20220110_193000.wav\t3"), tab)
  expect_warning(
    sc <- suppressMessages(score_detections(c(NOVO = tab), fit)),
    "not in the calibration")
  expect_identical(sc$night, c("20220109", "20220110"))
  expect_identical(sc$site, c("NOVO", "NOVO"))
})

test_that("detection_history() applies the repetition rule", {
  sc <- tibble::tibble(site = "S", species = "a",
                       night = c("1", "1", "1", "2", "3", "3"),
                       p_tp = c(0.99, 0.97, 0.5, 0.96, 0.99, 0.2))
  h <- detection_history(sc, p_min = 0.95, min_detections_night = 2)
  expect_identical(h$n_reliable, c(2L, 1L, 1L))
  expect_identical(h$detection_k1, c(1L, 1L, 1L))
  expect_identical(h$detection_k2, c(1L, 0L, 0L))
  expect_identical(h$detection_k3, c(0L, 0L, 0L))
  expect_identical(h$detection, h$detection_k2)
  expect_identical(summarise_history(h)$nights_k2, 1L)
})
