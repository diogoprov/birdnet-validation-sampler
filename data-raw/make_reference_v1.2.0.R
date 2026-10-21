# =============================================================================
# make_reference_v1.2.0.R
#
# Gera as saidas de referencia da v1.2.0 (ultima versao em scripts) sobre os
# dados simulados de tests/testthat/helper-simulate.R. Os testes do pacote
# comparam as funcoes com essas saidas, depois de renomear colunas e valores
# para os nomes em ingles.
#
# Cada cenario: extrai o script da tag v1.2.0 (git show), troca o bloco
# 'config' por um config.rds e roda num processo R separado. Caminhos
# absolutos da raiz simulada sao trocados por "<ROOT>".
#
# Uso (na raiz do repositorio): Rscript data-raw/make_reference_v1.2.0.R
# =============================================================================

source("tests/testthat/helper-simulate.R")

dir_ref <- "tests/testthat/fixtures/ref_v1.2.0"
unlink(dir_ref, recursive = TRUE)
dir.create(dir_ref, recursive = TRUE)

raiz <- file.path(tempdir(), "sim")
unlink(raiz, recursive = TRUE)
dir.create(raiz)
raiz <- normalizePath(raiz)
simulate_pam(raiz)

# Roda um script da tag com o config dado; devolve a pasta de trabalho
rodar_v120 <- function(script, config, nome) {
  trab <- file.path(raiz, "runs", nome)
  dir.create(trab, recursive = TRUE, showWarnings = FALSE)
  codigo <- system2("git", c("show", paste0("v1.2.0:", script)), stdout = TRUE)
  ini <- grep("^config <- list\\(", codigo)
  fim <- ini + grep("^\\)$", codigo[ini:length(codigo)])[1] - 1
  codigo <- c(codigo[seq_len(ini - 1)],
              sprintf('config <- readRDS("%s")', file.path(trab, "config.rds")),
              codigo[(fim + 1):length(codigo)])
  saveRDS(config, file.path(trab, "config.rds"))
  writeLines(codigo, file.path(trab, script))
  log <- file.path(trab, "log.txt")
  st <- system2("Rscript", file.path(trab, script), stdout = log, stderr = log)
  if (st != 0) stop("Failed: ", nome, "\n", paste(readLines(log), collapse = "\n"))
  trab
}

# Copia um csv para a referencia, trocando a raiz por <ROOT>
guardar <- function(origem, nome, arquivo = basename(origem)) {
  dir.create(file.path(dir_ref, nome), showWarnings = FALSE)
  txt <- readLines(origem)
  txt <- gsub(raiz, "<ROOT>", txt, fixed = TRUE)
  writeLines(txt, file.path(dir_ref, nome, arquivo))
}

# -----------------------------------------------------------------------------
# Etapa 1: extracao (simular = TRUE: so manifesto)
# -----------------------------------------------------------------------------

base_extracao <- list(
  dir_dados = file.path(raiz, "tabelas"),
  padrao_tabela = "^BirdNET_SelectionTable\\.txt$",
  modo_amostragem = "top", unidade_ocasiao = "arquivo", limiar = NULL,
  n_top = 2, fracao_gravacoes = 0.01, n_gravacoes_por_local = NULL,
  tabela_gravacoes = NULL, padrao_audio = "\\.(wav|flac|mp3)$",
  duracao_gravacao = NULL, conf_minima = 0.1, locais = NULL,
  data_inicio = NULL, data_fim = NULL, especies = NULL, hora_inicio = NULL,
  hora_fim = NULL, alternar_dias = FALSE, meta_total = NULL,
  balancear_por_hora = TRUE, max_por_especie = NULL,
  remap_de = "N:/Arara/", remap_para = paste0(raiz, "/"),
  fazer_zip = FALSE, simular = TRUE)

# Lista de gravacoes para o cenario rec_table (caminhos estilo Windows)
tab_grav <- file.path(raiz, "gravacoes.csv")
utils::write.csv(simulate_recordings_table(raiz), tab_grav, row.names = FALSE)

cenarios <- list(
  top_default = list(),
  top_meta = list(meta_total = 12, hora_inicio = 18, hora_fim = 2,
                  alternar_dias = TRUE),
  top_max = list(max_por_especie = 5, balancear_por_hora = FALSE,
                 especies = c("boa-ran", "den-nan"), data_inicio = "20220111",
                 data_fim = "20220115", locais = c("ARA", "XAR"),
                 limiar = 0.5, conf_minima = NULL),
  det_file = list(modo_amostragem = "aleatorio_deteccoes", limiar = 0.5,
                  n_top = 1),
  det_minute_meta = list(modo_amostragem = "aleatorio_deteccoes",
                         unidade_ocasiao = "minuto", limiar = 0.3, n_top = 1,
                         meta_total = 10),
  det_max = list(modo_amostragem = "aleatorio_deteccoes", limiar = 0.5,
                 max_por_especie = 4, balancear_por_hora = FALSE,
                 hora_inicio = 18, hora_fim = 23),
  rec_file = list(modo_amostragem = "aleatorio_gravacoes",
                  fracao_gravacoes = 0.25, limiar = 0.5,
                  duracao_gravacao = 180, especies = "boa-ran"),
  rec_minute = list(modo_amostragem = "aleatorio_gravacoes",
                    unidade_ocasiao = "minuto", n_gravacoes_por_local = 4,
                    duracao_gravacao = 180),
  rec_table = list(modo_amostragem = "aleatorio_gravacoes",
                   fracao_gravacoes = 0.5, tabela_gravacoes = tab_grav)
)

for (nm in names(cenarios)) {
  message("Extraction: ", nm)
  cfg <- utils::modifyList(base_extracao, cenarios[[nm]], keep.null = TRUE)
  cfg$dir_saida <- file.path(raiz, "runs", nm, "saida")
  invisible(rodar_v120("extrair_clipes_validacao.R", cfg, nm))
  guardar(file.path(cfg$dir_saida, "manifesto_clipes.csv"), nm)
  # caminhos da raiz simulada ficam como <ROOT> (os testes recriam a raiz)
  cen <- rapply(cenarios[[nm]], \(x) gsub(raiz, "<ROOT>", x, fixed = TRUE),
                classes = "character", how = "replace")
  saveRDS(cen, file.path(dir_ref, nm, "cenario.rds"))
}
# config base completa (os cenarios guardam so o que muda)
saveRDS(rapply(base_extracao, \(x) gsub(raiz, "<ROOT>", x, fixed = TRUE),
               classes = "character", how = "replace"),
        file.path(dir_ref, "base_extracao.rds"))

# -----------------------------------------------------------------------------
# Etapa 2: pos-validacao (revisao simulada sobre os manifestos)
# -----------------------------------------------------------------------------

for (nm in c("top_default", "rec_file")) {
  pv <- paste0("pv_", nm)
  message("Post-validation: ", pv)
  man <- file.path(raiz, "runs", nm, "saida", "manifesto_clipes.csv")
  m <- utils::read.csv(man)
  dir_rev <- file.path(raiz, "runs", pv, "revisado")
  simulate_review(m$arquivo_clipe, m$pasta_especie, m$confidence, dir_rev)
  cfg <- list(dir_validado = dir_rev, caminho_manifesto = man,
              dir_saida = file.path(raiz, "runs", pv, "resultados"),
              padrao_positivo = "positiv", padrao_negativo = "negativ",
              faixas = seq(0.1, 1, by = 0.1), precisao_alvo = 0.90,
              n_minimo = 15)
  invisible(rodar_v120("pos_validacao.R", cfg, pv))
  for (f in c("validacao_por_clipe.csv", "precisao_por_faixa.csv",
              "thresholds_sugeridos.csv", "presenca_por_noite.csv",
              "clipes_para_retreino.csv")) {
    guardar(file.path(cfg$dir_saida, f), pv)
  }
}

# -----------------------------------------------------------------------------
# Etapa 3: calibracao
# -----------------------------------------------------------------------------

message("Calibration")
dir_val <- file.path(raiz, "validacoes")
dir.create(dir_val, showWarnings = FALSE)
val <- simulate_validation()
arquivos_val <- character()
for (loc in names(val)) {
  f <- file.path(dir_val, paste0("validacao_por_clipe_", loc, ".csv"))
  utils::write.csv(val[[loc]], f, row.names = FALSE)
  arquivos_val <- c(arquivos_val, f)
}
dir.create(file.path(dir_ref, "cal"), showWarnings = FALSE)
invisible(file.copy(arquivos_val, file.path(dir_ref, "cal"), overwrite = TRUE))

cfg <- list(
  arquivos_validacao = arquivos_val,
  normalizar_locais = c("XAR2" = "XAR"),
  tabelas_predicao = c(
    ARA = file.path(raiz, "tabelas/output_ARA/BirdNET_SelectionTable.txt"),
    XAR = file.path(raiz, "tabelas/output_XAR/BirdNET_SelectionTable.txt"),
    BAI = file.path(raiz, "tabelas/BAI/BirdNET_SelectionTable.txt")),
  dir_saida = file.path(raiz, "runs", "cal", "calibracao"),
  conf_minima = 0.1, p_min = 0.95, min_deteccoes_noite = 1,
  hora_madrugada = 12, k_folds = 5, fazer_curva_esforco = TRUE,
  esforco_n = c(5, 10), esforco_repeticoes = 3, semente = 2026)
invisible(rodar_v120("calibracao.R", cfg, "cal"))
for (f in c("comparacao_modelos.csv", "curva_esforco.csv",
            "historico_deteccao_noite.csv",
            "resumo_deteccao_especie_local.csv",
            paste0("deteccoes_calibradas_", c("ARA", "XAR", "BAI"), ".csv"))) {
  guardar(file.path(cfg$dir_saida, f), "cal")
}

# -----------------------------------------------------------------------------
# Etapa 4: matrizes de comunidade
# -----------------------------------------------------------------------------

hist_sim <- file.path(raiz, "historico_simulado.csv")
utils::write.csv(simulate_history(), hist_sim, row.names = FALSE)
dir.create(file.path(dir_ref, "mat"), showWarnings = FALSE)
invisible(file.copy(hist_sim, file.path(dir_ref, "mat"), overwrite = TRUE))

for (k in 1:2) {
  nm <- paste0("mat_k", k)
  message("Matrices: ", nm)
  cfg <- list(dir_projeto = raiz, arquivo_historico = "historico_simulado.csv",
              dir_saida = file.path("runs", nm, "matrizes"), k_min = k,
              especies_nucleo = c("boa_ran", "den_nan", "sci_nas", "xxx_aus"),
              min_noites_mes = 5)
  invisible(rodar_v120("gerar_matrizes_comunidade.R", cfg, nm))
  d <- file.path(raiz, cfg$dir_saida)
  for (f in list.files(d, "\\.csv$")) guardar(file.path(d, f), nm)
}

message("References written to ", dir_ref)
