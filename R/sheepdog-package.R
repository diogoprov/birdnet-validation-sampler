#' @keywords internal
"_PACKAGE"

#' @import dplyr
#' @import purrr
#' @import stringr
#' @import tidyr
#' @importFrom readr read_csv read_tsv write_csv
#' @importFrom stats setNames
#' @importFrom tibble tibble
NULL

# Colunas usadas via tidy evaluation (evita NOTEs do R CMD check)
utils::globalVariables(c(
  ".N", ".dur", ".dia", ".n", ".ordem", ".p1", ".p2", "begin_path",
  "begin_time", "clip_end", "clip_start", "confidence", "duration",
  "end_time",
  "file_offset", "hour_int", "inclusion_prob", "n_detections_occasion",
  "night", "occasion_id", "pasta", "rank", "recording_date", "status",
  "recording_hour", "site", "source_audio", "species_code",
  "species_folder", "bin", "clip_file", "conf_meio", "low_support", "n_positive",
  "n_reviewed", "reviewed_path", "subpasta", "verdict", ".treino",
  "Confidence", "Species Code", "Begin Path", "File Offset (s)",
  "auc_mean", "date", "detection_k1", "detection_k2", "detection_k3",
  "faixa", "fold", "hour", "logit_conf", "n_reliable", "p_tp", "prec",
  "species", "tp"
))
