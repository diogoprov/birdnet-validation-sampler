# =============================================================================
# knit_bayesian_vignette.R
#
# vignette("bayesian-calibration") e pre-computada: os modelos Stan levam
# ~1 min para compilar, entao ela e tricotada aqui, localmente, a partir de
# vignettes/bayesian-calibration.Rmd.orig. O .Rmd resultante (com a saida) e
# as figuras em vignettes/bayes-figures/ vao para o repositorio.
#
# Uso (na raiz do repositorio, com brms, cmdstanr e priorsense instalados):
#   Rscript data-raw/knit_bayesian_vignette.R
# =============================================================================

devtools::install(quiet = TRUE, upgrade = FALSE)
old <- setwd("vignettes")
on.exit(setwd(old))
unlink("bayes-figures", recursive = TRUE)
knitr::knit("bayesian-calibration.Rmd.orig", "bayesian-calibration.Rmd")
