#' Read BirdNET selection tables
#'
#' Finds every BirdNET selection table (Raven format, tab-separated) under
#' `data_dir`, reads them and stacks them in one table. Each table holds the
#' predictions of one site, and the site is the name of the folder that
#' contains it. The `output_` prefix of BirdNET output folders is removed, so
#' `output_UEM/` becomes site `UEM`.
#'
#' Column names are standardised to lower case without units or punctuation,
#' e.g. `Begin Time (s)` becomes `begin_time` and `File Offset (s)` becomes
#' `file_offset`.
#'
#' @param data_dir Root folder, searched recursively.
#' @param table_pattern Regular expression for the table file names.
#'
#' @return A tibble with one row per prediction, the column `site` first,
#'   followed by the standardised table columns. The columns `begin_time`,
#'   `end_time`, `species_code`, `confidence`, `begin_path` and `file_offset`
#'   are required.
#' @export
read_selection_tables <- function(data_dir,
                                  table_pattern = "^BirdNET_SelectionTable\\.txt$") {
  tabelas <- list.files(data_dir, pattern = table_pattern,
                        recursive = TRUE, full.names = TRUE)
  if (length(tabelas) == 0) {
    stop("No selection table found in ", data_dir, " matching ",
         table_pattern)
  }
  message(length(tabelas), " selection table(s) found:")
  walk(tabelas, \(x) message("  - ", x))

  predicoes <- map(tabelas, function(tab) {
    if (file.size(tab) == 0) {
      warning("Empty table skipped: ", tab)
      return(NULL)
    }
    read_selection_table(tab) |>
      mutate(site = str_remove(basename(dirname(tab)), "^output_?"),
             .before = 1)
  }) |>
    list_rbind()

  if (nrow(predicoes) == 0) {
    stop("No prediction read - were all the tables found empty?")
  }
  message(nrow(predicoes), " predictions read from ",
          n_distinct(predicoes$site), " site(s).")
  predicoes
}

# Le uma tabela de selecao e padroniza os nomes: minusculas, sem
# unidades/pontuacao, espacos -> _
read_selection_table <- function(caminho) {
  tb <- read_tsv(caminho, show_col_types = FALSE,
                 na = c("", "NA"), progress = FALSE)

  nomes <- names(tb) |>
    str_to_lower() |>
    str_remove_all("\\((s|hz)\\)") |>
    str_trim() |>
    str_replace_all("[^a-z0-9]+", "_") |>
    str_remove("_$")
  names(tb) <- nomes

  obrigatorias <- c("begin_time", "end_time", "species_code",
                    "confidence", "begin_path", "file_offset")
  faltando <- setdiff(obrigatorias, names(tb))
  if (length(faltando) > 0) {
    stop("Table ", caminho, " lacks the columns: ",
         paste(faltando, collapse = ", "),
         "\nColumns found: ", paste(names(tb), collapse = ", "))
  }
  tb
}
