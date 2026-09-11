# =============================================================================
# calibracao.R
#
# Terceiro estagio do pipeline de validacao do FrogNet: calibra o confidence
# score do BirdNET em PROBABILIDADE de a deteccao ser verdadeira, usando os
# clipes validados manualmente (validacao_por_clipe.csv, gerados por
# pos_validacao.R), e aplica a calibracao a base COMPLETA de predicoes para
# construir os historicos de deteccao por noite.
#
# Fluxo (adaptado do protocolo de calibracao discutido por Larissa e Liliana):
#   1. Empilhar as validacoes (TP/FP) de todos os locais
#   2. Ajustar modelos candidatos: TP ~ logit(confidence) com estruturas
#      hierarquicas crescentes (especie, local, especie x local)
#   3. Comparar por validacao cruzada (k-fold estratificado) via AUC
#   4. Reajustar o melhor modelo com todos os dados
#   5. (opcional) Curva de esforco: quantos clipes validados por
#      local x especie sao necessarios para calibrar bem?
#   6. Prever P(TP) para TODAS as deteccoes das BirdNET_SelectionTable.txt
#      (somente especies presentes na calibracao)
#   7. Construir o historico de deteccao por local x especie x noite,
#      com regra de repeticao embutida como analise de sensibilidade
#
# Dependencias: dplyr, readr, stringr, purrr, tidyr, lme4, pROC, ggplot2
#   install.packages(c("dplyr","readr","stringr","purrr","tidyr",
#                      "lme4","pROC","ggplot2"))
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(purrr)
  library(tidyr)
  library(lme4)
  library(ggplot2)
})

# -----------------------------------------------------------------------------
# 1. CONFIGURACAO -- edite apenas este bloco
# -----------------------------------------------------------------------------

# Pasta do projeto no Mac (Box). Todos os insumos estao nela, com sufixo
# de local nos nomes.
dir_projeto <- "~/Library/CloudStorage/Box-Box/Meus Artigos/2026-codigo FrogNet"

config <- list(
  # validacao_por_clipe.csv de cada local (saida do pos_validacao.R)
  arquivos_validacao = file.path(dir_projeto, paste0(
    "validacao_por_clipe_",
    c("UEMS", "MIM", "ARA", "BAI", "XAR", "REF", "BEP"), ".csv")),

  # Corrigir nomes de local divergentes (manifesto da BEP saiu como "BEP2")
  normalizar_locais  = c("BEP2" = "BEP", "UEMS" = "UEM"),

  # Tabelas COMPLETAS de predicao do BirdNET, nomeadas pelo local
  # (usadas no passo 6; comente as que nao quiser pontuar agora)
  tabelas_predicao = c(
    UEM = file.path(dir_projeto, "BirdNET_SelectionTable_UEMS.txt"),
    MIM = file.path(dir_projeto, "BirdNET_SelectionTable_MIM.txt"),
    ARA = file.path(dir_projeto, "BirdNET_SelectionTable_ARA.txt"),
    BAI = file.path(dir_projeto, "BirdNET_SelectionTable_BAI.txt"),
    XAR = file.path(dir_projeto, "BirdNET_SelectionTable_XAR.txt"),
    REF = file.path(dir_projeto, "BirdNET_SelectionTable_REF.txt"),
    BEP = file.path(dir_projeto, "BirdNET_SelectionTable_BEP.txt")
  ),

  # ATENCAO: os deteccoes_calibradas_<LOC>.csv somam ~700 MB nos 7 locais
  # e, dentro da pasta do Box, serao SINCRONIZADOS para a nuvem. Se nao
  # quiser isso, troque por uma pasta local, ex.: "~/FrogNet_calibracao"
  dir_saida          = file.path(dir_projeto, "calibracao"),

  # Deteccoes abaixo disso nao entram na base pontuada
  conf_minima        = 0.1,

  # Threshold sobre a PROBABILIDADE CALIBRADA (nao sobre o confidence!)
  p_min              = 0.95,

  # Regra de repeticao: n minimo de deteccoes confiaveis para marcar
  # presenca na noite (o historico tambem sai com k = 1, 2 e 3 para
  # analise de sensibilidade)
  min_deteccoes_noite = 1,

  # Horas < hora_madrugada pertencem a noite da vespera
  hora_madrugada     = 12,

  # Validacao cruzada
  k_folds            = 5,

  # Curva de esforco (passo 5) -- demorada; ligue quando quiser
  fazer_curva_esforco = FALSE,
  esforco_n          = c(5, 10, 15, 20, 25, 30),
  esforco_repeticoes = 50,

  semente            = 2026
)

# -----------------------------------------------------------------------------
# 2. EMPILHAR AS VALIDACOES
# -----------------------------------------------------------------------------

logit_seguro <- function(p) qlogis(pmin(pmax(p, 1e-4), 1 - 1e-4))

normalizar_local <- function(x, mapa) {
  ifelse(x %in% names(mapa), unname(mapa[x]), x)
}

val <- map(config$arquivos_validacao, function(f) {
  if (!file.exists(f)) { warning("Nao encontrado: ", f); return(NULL) }
  read_csv(f, show_col_types = FALSE, progress = FALSE)
}) |>
  list_rbind() |>
  filter(veredito %in% c("positivo", "negativo")) |>
  transmute(
    local      = normalizar_local(local, config$normalizar_locais),
    especie    = pasta_especie,
    confidence = confidence,
    logit_conf = logit_seguro(confidence),
    tp         = as.integer(veredito == "positivo")
  ) |>
  mutate(across(c(local, especie), as.factor))

if (nrow(val) == 0) stop("Nenhum clipe validado encontrado.")
message(nrow(val), " clipes validados (", sum(val$tp), " TP / ",
        sum(val$tp == 0), " FP) de ", n_distinct(val$especie),
        " especies em ", n_distinct(val$local), " locais.")

esp_calibradas <- levels(val$especie)

# -----------------------------------------------------------------------------
# 3. MODELOS CANDIDATOS E VALIDACAO CRUZADA
# -----------------------------------------------------------------------------

modelos <- list(
  m0_global          = tp ~ logit_conf,
  m1_int_especie     = tp ~ logit_conf + (1 | especie),
  m2_slope_especie   = tp ~ logit_conf + (logit_conf | especie),
  m3_mais_local      = tp ~ logit_conf + (logit_conf | especie) + (1 | local),
  m4_especie_x_local = tp ~ logit_conf + (logit_conf | especie) +
                            (1 | local:especie)
)

ajustar <- function(formula, dados) {
  if (length(findbars(formula)) == 0) {
    glm(formula, data = dados, family = binomial)
  } else {
    suppressMessages(glmer(
      formula, data = dados, family = binomial,
      control = glmerControl(optimizer = "bobyqa",
                             optCtrl = list(maxfun = 1e5))))
  }
}

prever <- function(modelo, dados) {
  if (inherits(modelo, "merMod")) {
    predict(modelo, newdata = dados, type = "response",
            allow.new.levels = TRUE)
  } else {
    predict(modelo, newdata = dados, type = "response")
  }
}

# folds estratificados dentro de cada local x especie, para todo nivel
# aparecer tanto no treino quanto no teste
set.seed(config$semente)
val <- val |>
  group_by(local, especie) |>
  mutate(fold = sample(rep_len(seq_len(config$k_folds), n()))) |>
  ungroup()

message("Validacao cruzada (", config$k_folds, " folds) de ",
        length(modelos), " modelos...")
cv <- map(names(modelos), function(nm) {
  aucs <- map_dbl(seq_len(config$k_folds), function(k) {
    treino <- filter(val, fold != k)
    teste  <- filter(val, fold == k)
    fit    <- tryCatch(ajustar(modelos[[nm]], treino),
                       error = function(e) NULL)
    if (is.null(fit)) return(NA_real_)
    as.numeric(pROC::auc(pROC::roc(
      teste$tp, prever(fit, teste), quiet = TRUE)))
  })
  tibble(modelo = nm, formula = deparse1(modelos[[nm]]),
         auc_media = mean(aucs, na.rm = TRUE),
         auc_dp = sd(aucs, na.rm = TRUE))
}) |>
  list_rbind() |>
  arrange(desc(auc_media))

dir.create(config$dir_saida, recursive = TRUE, showWarnings = FALSE)
write_csv(cv, file.path(config$dir_saida, "comparacao_modelos.csv"))
message("AUC por modelo:")
print(as.data.frame(cv), digits = 3)

melhor <- cv$modelo[1]
message("Melhor modelo: ", melhor)

# -----------------------------------------------------------------------------
# 4. REAJUSTE FINAL E DIAGNOSTICO
# -----------------------------------------------------------------------------

fit_final <- ajustar(modelos[[melhor]], val)
saveRDS(fit_final, file.path(config$dir_saida, "modelo_calibracao.rds"))
capture.output(summary(fit_final),
               file = file.path(config$dir_saida, "modelo_calibracao.txt"))

# curvas calibradas por especie x local (grade de confidence)
grade <- expand_grid(
  especie = factor(esp_calibradas, levels = esp_calibradas),
  local   = factor(levels(val$local), levels = levels(val$local)),
  confidence = seq(config$conf_minima, 0.99, by = 0.01)
) |>
  mutate(logit_conf = logit_seguro(confidence),
         p_tp = prever(fit_final, pick(everything())))

obs_faixa <- val |>
  mutate(faixa = pmin(floor(confidence * 10) / 10 + 0.05, 0.95)) |>
  group_by(especie, local, faixa) |>
  summarise(prec = mean(tp), n = n(), .groups = "drop")

g <- ggplot(grade, aes(confidence, p_tp, colour = local)) +
  geom_hline(yintercept = config$p_min, linetype = "dashed",
             colour = "grey50") +
  geom_line(linewidth = 0.5) +
  geom_point(data = obs_faixa,
             aes(faixa, prec, size = n, colour = local), alpha = 0.4) +
  scale_size_continuous(range = c(0.5, 3), name = "clipes validados") +
  facet_wrap(~ especie) +
  labs(x = "Confidence do BirdNET", y = "P(deteccao verdadeira) calibrada",
       title = "Calibracao score -> probabilidade, por especie e local",
       subtitle = paste0("Modelo: ", melhor,
                         " | linha tracejada: p_min = ", config$p_min)) +
  theme_minimal(base_size = 10)
ggsave(file.path(config$dir_saida, "curvas_calibradas.png"), g,
       width = 13, height = 9, dpi = 200, bg = "white")

# -----------------------------------------------------------------------------
# 5. CURVA DE ESFORCO (opcional)
# -----------------------------------------------------------------------------

if (isTRUE(config$fazer_curva_esforco)) {
  message("Curva de esforco (", config$esforco_repeticoes,
          " repeticoes por n)...")
  set.seed(config$semente)
  esforco <- map(config$esforco_n, function(n_treino) {
    aucs <- map_dbl(seq_len(config$esforco_repeticoes), function(r) {
      amostra <- val |>
        group_by(local, especie) |>
        mutate(.treino = seq_len(n()) %in%
                 sample(seq_len(n()), min(n_treino, max(n() - 5, 1)))) |>
        ungroup()
      treino <- filter(amostra, .treino)
      teste  <- filter(amostra, !.treino)
      if (nrow(teste) < 50) return(NA_real_)
      fit <- tryCatch(ajustar(modelos[[melhor]], treino),
                      error = function(e) NULL)
      if (is.null(fit)) return(NA_real_)
      as.numeric(pROC::auc(pROC::roc(
        teste$tp, prever(fit, teste), quiet = TRUE)))
    })
    tibble(n_por_celula = n_treino,
           auc_media = mean(aucs, na.rm = TRUE),
           auc_dp = sd(aucs, na.rm = TRUE))
  }) |> list_rbind()
  write_csv(esforco, file.path(config$dir_saida, "curva_esforco.csv"))
  print(as.data.frame(esforco), digits = 3)
}

# -----------------------------------------------------------------------------
# 6. PONTUAR A BASE COMPLETA DE PREDICOES
# -----------------------------------------------------------------------------

codigo_curto <- function(x) str_replace_all(str_extract(x, "[^_]+$"), "-", "_")

pontuar_local <- function(caminho, loc) {
  if (!file.exists(caminho)) {
    warning("Tabela nao encontrada para ", loc, ": ", caminho)
    return(NULL)
  }
  message("Pontuando ", loc, " (", caminho, ")...")
  tb <- read_tsv(caminho, show_col_types = FALSE, progress = FALSE,
                 col_select = c(`Species Code`, Confidence,
                                `Begin Path`, `File Offset (s)`))
  names(tb) <- c("species_code", "confidence", "begin_path", "file_offset")
  m <- str_match(basename(tb$begin_path), "(\\d{8})_(\\d{6})")
  tb <- tb |>
    mutate(
      especie = codigo_curto(species_code),
      data    = m[, 2],
      hora    = as.integer(str_sub(m[, 3], 1, 2)),
      noite   = if_else(hora < config$hora_madrugada,
                        format(as.Date(data, "%Y%m%d") - 1, "%Y%m%d"),
                        data),
      local   = loc
    ) |>
    filter(confidence >= config$conf_minima)

  fora <- sum(!tb$especie %in% esp_calibradas)
  tb <- filter(tb, especie %in% esp_calibradas)
  message("  ", nrow(tb), " deteccoes de especies calibradas (",
          fora, " de especies NAO calibradas foram excluidas).")
  if (nrow(tb) == 0) return(NULL)

  tb <- tb |>
    mutate(logit_conf = logit_seguro(confidence),
           especie = factor(especie, levels = esp_calibradas),
           local   = factor(local, levels = levels(val$local)),
           p_tp    = prever(fit_final, pick(everything())))
  write_csv(select(tb, local, especie, data, noite, hora, confidence,
                   p_tp, begin_path, file_offset),
            file.path(config$dir_saida,
                      paste0("deteccoes_calibradas_", loc, ".csv")))
  tb
}

pontuadas <- imap(config$tabelas_predicao, pontuar_local) |>
  compact() |>
  list_rbind()

if (nrow(pontuadas) > 0) {

# -----------------------------------------------------------------------------
# 7. HISTORICO DE DETECCAO POR NOITE (com sensibilidade a regra de repeticao)
# -----------------------------------------------------------------------------

historico <- pontuadas |>
  group_by(local, especie, noite) |>
  summarise(
    n_deteccoes      = n(),
    n_confiaveis     = sum(p_tp >= config$p_min),
    p_tp_max         = max(p_tp),
    deteccao_k1      = as.integer(n_confiaveis >= 1),
    deteccao_k2      = as.integer(n_confiaveis >= 2),
    deteccao_k3      = as.integer(n_confiaveis >= 3),
    .groups = "drop"
  ) |>
  mutate(deteccao = as.integer(n_confiaveis >= config$min_deteccoes_noite))

write_csv(historico,
          file.path(config$dir_saida, "historico_deteccao_noite.csv"))

resumo <- historico |>
  group_by(local, especie) |>
  summarise(noites = n(),
            noites_k1 = sum(deteccao_k1), noites_k2 = sum(deteccao_k2),
            noites_k3 = sum(deteccao_k3), .groups = "drop")
write_csv(resumo,
          file.path(config$dir_saida, "resumo_deteccao_especie_local.csv"))

message("\nNoites com deteccao confiavel (p_tp >= ", config$p_min,
        "), por regra de repeticao:")
print(as.data.frame(count(historico, deteccao_k1, deteccao_k2,
                          deteccao_k3)))
}

message("\nPronto! Saidas em ", config$dir_saida,
        "\nO historico_deteccao_noite.csv e o insumo das analises; a coluna",
        "\n'deteccao' usa k = ", config$min_deteccoes_noite,
        "; as colunas deteccao_k1/k2/k3 dao a sensibilidade a regra.")
