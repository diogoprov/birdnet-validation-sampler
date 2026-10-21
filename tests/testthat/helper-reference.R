# Acesso as saidas de referencia da v1.2.0 (fixtures/ref_v1.2.0), geradas
# por data-raw/make_reference_v1.2.0.R

ref_path <- function(...) test_path("fixtures", "ref_v1.2.0", ...)

# Raiz simulada (a mesma de make_reference_v1.2.0.R), criada uma vez por
# sessao de testes
sim_root <- local({
  raiz <- NULL
  function() {
    if (is.null(raiz)) {
      raiz <<- file.path(tempdir(), "sheepdog-sim")
      unlink(raiz, recursive = TRUE)
      dir.create(raiz)
      raiz <<- normalizePath(raiz)
      simulate_pam(raiz)
      utils::write.csv(simulate_recordings_table(raiz),
                       file.path(raiz, "gravacoes.csv"), row.names = FALSE)
    }
    raiz
  }
})

# Nomes dos argumentos da v1.2.0 (config) -> argumentos do pacote
legacy_args <- c(
  modo_amostragem = "sampling_mode", unidade_ocasiao = "occasion_unit",
  limiar = "threshold", n_top = "n_top",
  fracao_gravacoes = "recording_fraction",
  n_gravacoes_por_local = "n_recordings_per_site",
  tabela_gravacoes = "recordings", padrao_audio = "audio_pattern",
  duracao_gravacao = "recording_duration", conf_minima = "min_confidence",
  locais = "sites", data_inicio = "date_start", data_fim = "date_end",
  especies = "species", hora_inicio = "hour_start", hora_fim = "hour_end",
  alternar_dias = "alternate_days", meta_total = "target_total",
  balancear_por_hora = "balance_by_hour", max_por_especie = "max_per_species",
  remap_de = "remap_from", remap_para = "remap_to"
)
legacy_arg_values <- c(aleatorio_deteccoes = "random_detections",
                       aleatorio_gravacoes = "random_recordings",
                       arquivo = "file", minuto = "minute")

# Argumentos de select_clips() equivalentes ao config de um cenario
scenario_args <- function(nome) {
  raiz <- sim_root()
  cfg <- utils::modifyList(readRDS(ref_path("base_extracao.rds")),
                           readRDS(ref_path(nome, "cenario.rds")),
                           keep.null = TRUE)
  cfg <- cfg[intersect(names(cfg), names(legacy_args))]
  cfg <- lapply(cfg, function(x) {
    if (!is.character(x)) return(x)
    x <- sub("<ROOT>", raiz, x, fixed = TRUE)
    ifelse(x %in% names(legacy_arg_values), legacy_arg_values[x], x)
  })
  stats::setNames(cfg, legacy_args[names(cfg)])
}

# Le um csv como texto (todas as colunas character), para comparar
# exatamente o que foi escrito
read_as_text <- function(caminho) {
  readr::read_csv(caminho, col_types = readr::cols(.default = "c"),
                  na = character(), progress = FALSE)
}

# Escreve uma tabela como o pacote escreve e le de volta como texto,
# trocando a raiz simulada por <ROOT>
as_written <- function(df) {
  f <- tempfile(fileext = ".csv")
  readr::write_csv(df, f)
  txt <- gsub(sim_root(), "<ROOT>", readLines(f), fixed = TRUE)
  writeLines(txt, f)
  read_as_text(f)
}

# Referencia da v1.2.0 convertida para os nomes atuais
ref_table <- function(...) {
  ref <- read_as_text(ref_path(...))
  # recodifica os valores lidos como texto ("NA" continua "NA")
  out <- sheepdog:::from_legacy(ref)
  if ("clip_file" %in% names(out)) {
    out$clip_file <- sub("^grav_", "rec_", out$clip_file)
  }
  out
}
