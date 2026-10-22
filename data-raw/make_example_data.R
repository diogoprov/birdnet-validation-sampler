# =============================================================================
# make_example_data.R
#
# Gera o conjunto de exemplo das vignettes em inst/extdata/example/:
#   birdnet/<SITE>/BirdNET_SelectionTable.txt - predicoes simuladas (Raven)
#                                               de 4 locais x 6 meses
#   recordings.csv                            - todas as gravacoes, com ou
#                                               sem predicao
#   validation/validation_by_clip_<SITE>.csv  - clipes "top" revisados (o
#                                               veredito vem da verdade
#                                               simulada)
#   nightly_detection_history.csv             - historico calibrado
#                                               (saida de calibrate())
#
# Modelo da simulacao: cada especie ocupa cada local x mes com uma
# probabilidade propria; quando presente, cada gravacao tem deteccoes
# verdadeiras (confidence de uma Beta especifica da especie). Toda especie
# tem tambem falsos positivos em toda gravacao, presente ou nao, com
# confidence de uma Beta que se sobrepoe a das verdadeiras e taxa que varia
# por especie e por local (locais mais ruidosos). Assim, o mesmo score
# corresponde a probabilidades de acerto diferentes entre especies e locais.
# Um gravador falha no fim de out/2021 em XAR (menos noites nesse mes). Os audios nao existem: Begin Path aponta para um NAS ficticio
# (N:\pam\...), remapeado nas vignettes quando preciso.
#
# Uso (na raiz do repositorio): Rscript data-raw/make_example_data.R
# =============================================================================

devtools::load_all(quiet = TRUE)
library(dplyr)

set.seed(2026)

especies <- tibble::tribble(
  ~species_code,                    ~a_tp, ~b_tp, ~lambda_tp, ~mu_fp, ~a_fp, ~b_fp,
  "Boana raniceps_boa-ran",           5,     2,      3.0,      0.6,    2.0,   4.0,
  "Dendropsophus nanus_den-nan",      3,     2,      3.5,      1.5,    2.0,   3.0,
  "Scinax nasicus_sci-nas",           3,     2,      2.0,      1.5,    2.5,   3.0,
  "Leptodactylus fuscus_lep-fus",     4,     3,      1.5,      0.8,    2.0,   4.0,
  "Pseudis platensis_pse-pla",        2.5,   2,      1.5,      2.0,    2.5,   2.5
)
locais <- c("ARA", "XAR", "BAI", "NHE")
# multiplicador da taxa de falsos positivos por local (ruido de fundo)
ruido  <- c(ARA = 0.7, XAR = 1.5, BAI = 1.0, NHE = 2.2)
meses  <- seq(as.Date("2021-10-01"), by = "month", length.out = 6)
horas  <- c("190000", "220000", "010000")
dur    <- 300

# Ocupacao por local x mes: a sazonalidade (chuva de nov a fev) e o local
# mudam a probabilidade de cada especie
psi <- expand.grid(site = locais, mes = format(meses, "%Y%m"),
                   species_code = especies$species_code,
                   stringsAsFactors = FALSE) |>
  mutate(
    chuva = substr(mes, 5, 6) %in% c("11", "12", "01", "02"),
    base  = c(ARA = 0.3, XAR = 0, BAI = -0.4, NHE = 0.1)[site] +
      c(0.8, 0.6, 0, -0.8, -0.3)[match(species_code, especies$species_code)],
    psi   = plogis(base + ifelse(chuva, 1.2, -1.0)),
    presente = runif(n()) < psi
  )

gravacoes <- expand.grid(site = locais, mes = meses, noite = 1:5,
                         hora = horas, stringsAsFactors = FALSE) |>
  # falha do gravador de XAR: so 3 noites em out/2021
  filter(!(site == "XAR" & mes == meses[1] & noite > 3)) |>
  mutate(
    data = mes + (noite - 1) * 5,
    # a madrugada pertence a noite anterior, mas o arquivo tem a data do dia
    data = if_else(hora == "010000", data + 1, data),
    arquivo = sprintf("%s01_%s_%s.wav", site, format(data, "%Y%m%d"), hora),
    begin_path = paste0("N:\\pam\\audio\\", site, "\\", arquivo),
    mes = format(mes, "%Y%m")
  ) |>
  arrange(site, arquivo)

# Uma linha por deteccao, com a verdade (tp) guardada a parte
deteccoes <- gravacoes |>
  tidyr::crossing(especies) |>
  left_join(select(psi, site, mes, species_code, presente),
            by = c("site", "mes", "species_code")) |>
  mutate(n_tp = if_else(presente, rpois(n(), lambda_tp), 0L),
         n_fp = rpois(n(), mu_fp * ruido[site])) |>
  rowwise() |>
  mutate(det = list(tibble(
    tp = rep(c(1L, 0L), c(n_tp, n_fp)),
    confidence = round(c(rbeta(n_tp, a_tp, b_tp), rbeta(n_fp, a_fp, b_fp)), 4)
  ))) |>
  ungroup() |>
  select(site, arquivo, begin_path, species_code, det) |>
  tidyr::unnest(det) |>
  filter(confidence >= 0.1) |>
  group_by(site, arquivo) |>
  # posicoes distintas (multiplos de 3 s) dentro da gravacao
  mutate(file_offset = sample(seq(0, dur - 3, by = 3), n())) |>
  ungroup() |>
  arrange(site, arquivo, file_offset)

raiz <- "inst/extdata/example"
unlink(raiz, recursive = TRUE)

# Selection tables no formato Raven do BirdNET; Begin Time acumula as
# duracoes, como nas tabelas concatenadas por local
for (loc in locais) {
  d <- filter(deteccoes, site == loc) |>
    mutate(inicio_arquivo = (match(arquivo, unique(arquivo)) - 1) * dur)
  tab <- data.frame(
    "Selection" = seq_len(nrow(d)), "View" = "Spectrogram 1", "Channel" = 1,
    "Begin Time (s)" = d$inicio_arquivo + d$file_offset,
    "End Time (s)" = d$inicio_arquivo + d$file_offset + 3,
    "Low Freq (Hz)" = 0, "High Freq (Hz)" = 15000,
    "Species Code" = d$species_code,
    "Common Name" = sub("_.*$", "", d$species_code),
    "Confidence" = d$confidence, "Begin Path" = d$begin_path,
    "File Offset (s)" = d$file_offset, check.names = FALSE)
  dir.create(file.path(raiz, "birdnet", loc), recursive = TRUE)
  utils::write.table(tab, file.path(raiz, "birdnet", loc,
                                    "BirdNET_SelectionTable.txt"),
                     sep = "\t", quote = FALSE, row.names = FALSE)
}

readr::write_csv(transmute(gravacoes, site, source_audio = begin_path),
                 file.path(raiz, "recordings.csv"))

# Validacao "top": as 2 maiores confidences por local x especie x noite x
# hora (janela 18h-2h, a madrugada conta como a noite anterior), ate 80
# clipes por local x especie; veredito = verdade simulada
det <- suppressMessages(read_selection_tables(file.path(raiz, "birdnet")))
manifesto <- suppressMessages(select_clips(det, n_top = 2,
                                           hour_start = 18, hour_end = 2,
                                           max_per_species = 80))
verdade <- deteccoes |>
  transmute(site, species_code, file_offset,
            begin_path, tp)
validacao <- manifesto |>
  left_join(verdade, by = c("site", "species_code", "begin_path",
                            "clip_start" = "file_offset")) |>
  mutate(verdict = if_else(tp == 1L, "positive", "negative"),
         reviewed_path = NA_character_) |>
  select(-tp)
stopifnot(!anyNA(validacao$verdict))
dir.create(file.path(raiz, "validation"))
for (loc in locais) {
  readr::write_csv(filter(validacao, site == loc),
                   file.path(raiz, "validation",
                             paste0("validation_by_clip_", loc, ".csv")))
}

# Historico calibrado para a vignette das matrizes de comunidade
saida <- file.path(tempdir(), "exemplo-calibracao")
suppressMessages(calibrate(
  validation_files = list.files(file.path(raiz, "validation"),
                                full.names = TRUE),
  prediction_tables = setNames(file.path(raiz, "birdnet", locais,
                                         "BirdNET_SelectionTable.txt"),
                               locais),
  output_dir = saida))
file.copy(file.path(saida, "nightly_detection_history.csv"),
          file.path(raiz, "nightly_detection_history.csv"), overwrite = TRUE)

message("Exemplo em ", raiz, ": ", nrow(deteccoes), " deteccoes, ",
        nrow(gravacoes), " gravacoes, ", nrow(validacao),
        " clipes validados (", round(mean(validacao$verdict == "positive"), 2),
        " positivos)")
