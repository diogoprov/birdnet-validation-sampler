# =============================================================================
# check_translations.R
#
# As traducoes em vignettes/articles/pt/ registram, em translations.csv, o
# md5 do arquivo em ingles que traduziram. Este script compara com o md5
# atual e avisa quando o original mudou depois da traducao (a traducao
# precisa ser revista). No GitHub Actions o aviso aparece como anotacao.
#
# Uso (na raiz do repositorio): Rscript data-raw/check_translations.R
# Depois de rever uma traducao, atualize source_md5, package_version e
# date na linha dela em translations.csv.
# =============================================================================

reg <- utils::read.csv("vignettes/articles/pt/translations.csv")
atual <- unname(tools::md5sum(reg$source))
desatualizadas <- reg[is.na(atual) | atual != reg$source_md5, ]

if (nrow(desatualizadas) == 0) {
  message("Translations up to date with their English sources.")
} else {
  em_gha <- nzchar(Sys.getenv("GITHUB_ACTIONS"))
  for (i in seq_len(nrow(desatualizadas))) {
    txt <- sprintf("Translation vignettes/articles/pt/%s is out of date: %s changed after the translation (package %s, %s).",
                   desatualizadas$translation[i], desatualizadas$source[i],
                   desatualizadas$package_version[i], desatualizadas$date[i])
    if (em_gha) cat("::warning::", txt, "\n", sep = "") else message(txt)
  }
}
