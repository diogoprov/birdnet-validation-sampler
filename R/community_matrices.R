#' Community matrices from the detection history
#'
#' Turns the calibrated nightly detection history into site x month
#' community matrices for multivariate ordinations (PCoA, NMDS, RDA).
#' Because those analyses do not model false positives, the entry rule is
#' strict:
#' * a species counts as detected on a night only when it had at least
#'   `k_min` reliable detections that night, i.e. detections with a
#'   calibrated probability >= `p_min` of [calibrate()] (column
#'   `detection_k<k_min>` of the history);
#' * only the core species enter the matrix: species whose calibration is
#'   reliable at every site. Other species would create artefactual beta
#'   diversity from differences in classifier recall among sites;
#' * each cell is the frequency of nights with detection, standardised by
#'   effort: nights with detection / nights recorded at that site x month.
#'
#' Effort (nights recorded) is approximated by the number of distinct
#' nights in the history of the site, for any species. With dense
#' detections, every night actually recorded appears in the history.
#'
#' @param history Nightly detection history, as returned by
#'   [detection_history()] (v1.2.0 `historico_deteccao_noite.csv` tables
#'   are also accepted).
#' @param core_species Species codes (the `species` column) that enter the
#'   matrix.
#' @param k_min Repetition rule: 1, 2 or 3 reliable detections on the night.
#' @param min_nights_month Site x month cells with fewer recorded nights are
#'   dropped from the matrices (unstable frequencies) and flagged in
#'   `effort`.
#'
#' @return A list with three tibbles: `frequency` and `counts` (one row per
#'   site x month, with `site`, `month`, `n_nights_recorded` and one column
#'   per core species) and `effort` (`site`, `month`, `n_nights_recorded`,
#'   `included`).
#' @export
community_matrices <- function(history, core_species, k_min = 2,
                               min_nights_month = 5) {
  if (length(core_species) == 0) stop("`core_species` is empty.")
  historico <- from_legacy(history) |>
    mutate(night = as.character(night))

  col_k <- paste0("detection_k", k_min)
  if (!col_k %in% names(historico)) {
    stop("Column ", col_k, " is not in the history.")
  }

  faltantes <- setdiff(core_species, unique(historico$species))
  if (length(faltantes) > 0) {
    warning("Core species missing from the history: ",
            paste(faltantes, collapse = ", "))
  }

  # esforco: noites gravadas por local x mes (todas as especies contam)
  historico <- historico |>
    mutate(month = str_c(str_sub(night, 1, 4), "-", str_sub(night, 5, 6)))

  esforco <- historico |>
    distinct(site, month, night) |>
    count(site, month, name = "n_nights_recorded") |>
    mutate(included = n_nights_recorded >= min_nights_month)

  # noites com deteccao por local x mes x especie (regra k_min, so nucleo)
  deteccoes <- historico |>
    filter(species %in% core_species, .data[[col_k]] == 1) |>
    count(site, month, species, name = "n_nights_detected")

  longo <- esforco |>
    filter(included) |>
    select(site, month, n_nights_recorded) |>
    crossing(species = core_species) |>
    left_join(deteccoes, by = c("site", "month", "species")) |>
    mutate(
      n_nights_detected = replace_na(n_nights_detected, 0L),
      frequency = n_nights_detected / n_nights_recorded
    )

  # matrizes largas (linhas = local x mes; colunas = especies)
  frequencia <- longo |>
    select(site, month, n_nights_recorded, species, frequency) |>
    pivot_wider(names_from = species, values_from = frequency) |>
    arrange(site, month)

  contagens <- longo |>
    select(site, month, n_nights_recorded, species, n_nights_detected) |>
    pivot_wider(names_from = species, values_from = n_nights_detected) |>
    arrange(site, month)

  list(frequency = frequencia, counts = contagens, effort = esforco)
}

#' Write the community matrices
#'
#' Reads the nightly detection history written by [calibrate()] and writes
#' the matrices of [community_matrices()] to `output_dir`:
#' `frequency_matrix_site_month_k<k>.csv`,
#' `count_matrix_site_month_k<k>.csv` and `effort_site_month.csv` (which
#' also lists the dropped cells). This is the function form of the v1.2.0
#' script `gerar_matrizes_comunidade.R`.
#'
#' @inheritParams community_matrices
#' @param history_file Path to `nightly_detection_history.csv` (or a v1.2.0
#'   `historico_deteccao_noite.csv`).
#' @param output_dir Output folder; created if needed.
#'
#' @return The list returned by [community_matrices()], invisibly.
#' @export
build_community_matrices <- function(history_file, output_dir, core_species,
                                     k_min = 2, min_nights_month = 5) {
  if (!file.exists(history_file)) stop("History not found: ", history_file)
  # a noite (AAAAMMDD) e lida como texto, no formato novo ou no antigo
  cols_noite <- intersect(c("night", "noite"),
                          names(read_csv(history_file, n_max = 0,
                                         show_col_types = FALSE)))
  historico <- read_csv(
    history_file, show_col_types = FALSE,
    col_types = readr::cols(!!!setNames(rep(list(readr::col_character()),
                                            length(cols_noite)), cols_noite),
                            .default = readr::col_guess()))
  mats <- community_matrices(historico, core_species, k_min,
                             min_nights_month)

  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
  sufixo <- paste0("site_month_k", k_min)
  write_csv(mats$frequency,
            file.path(output_dir, paste0("frequency_matrix_", sufixo, ".csv")))
  write_csv(mats$counts,
            file.path(output_dir, paste0("count_matrix_", sufixo, ".csv")))
  write_csv(mats$effort, file.path(output_dir, "effort_site_month.csv"))

  n_desc <- sum(!mats$effort$included)
  message("Matrix: ", nrow(mats$frequency), " rows (site x month) x ",
          length(core_species), " species | rule k >= ", k_min)
  message("Effort: ", sum(mats$effort$included), " site x month cells ",
          "included; ", n_desc, " dropped for having < ", min_nights_month,
          " recorded nights (see effort_site_month.csv)")
  message("Files in: ", output_dir)
  invisible(mats)
}
