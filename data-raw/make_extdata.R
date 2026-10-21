# =============================================================================
# make_extdata.R
#
# Gera os arquivos de exemplo do contrato com o crywolf em inst/extdata/:
#   clip_manifest.csv       - manifesto de random_detections (ocasiao =
#                             arquivo, limiar 0.5), com status
#   validation_by_clip.csv  - o mesmo manifesto depois da revisao simulada
# a partir dos dados simulados de tests/testthat/helper-simulate.R.
# Caminhos da raiz simulada viram "/project".
#
# Uso (na raiz do repositorio): Rscript data-raw/make_extdata.R
# =============================================================================

devtools::load_all(quiet = TRUE)
source("tests/testthat/helper-simulate.R")

raiz <- file.path(tempdir(), "sim-extdata")
unlink(raiz, recursive = TRUE)
dir.create(raiz)
raiz <- normalizePath(raiz)
simulate_pam(raiz)

saida <- file.path(raiz, "saida")
manifesto <- suppressMessages(extract_validation_clips(
  file.path(raiz, "tabelas"), saida,
  sampling_mode = "random_detections", threshold = 0.5, n_top = 1,
  sites = "ARA", species = "boa-ran", max_per_species = 6,
  remap_from = "N:/Arara/", remap_to = paste0(raiz, "/"), simulate = TRUE))

# o exemplo representa uma rodada com corte real (aqui o corte foi
# simulado, os .wav simulados sao vazios)
manifesto$status <- "ok"

dir_rev <- file.path(raiz, "revisado")
simulate_review(manifesto$clip_file, manifesto$species_folder,
                manifesto$confidence, dir_rev)
validacao <- suppressMessages(classify_review(manifesto, dir_rev))

limpar <- function(df) {
  df[] <- lapply(df, \(x) if (is.character(x)) {
    gsub(raiz, "/project", x, fixed = TRUE)
  } else x)
  df
}

dir.create("inst/extdata", recursive = TRUE, showWarnings = FALSE)
readr::write_csv(limpar(manifesto), "inst/extdata/clip_manifest.csv")
readr::write_csv(limpar(validacao), "inst/extdata/validation_by_clip.csv")
message("Exemplos em inst/extdata/")
