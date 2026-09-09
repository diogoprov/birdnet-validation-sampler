# =============================================================================
# pos_validacao.R
#
# Fecha o ciclo da validacao manual (projeto FrogNet): le o resultado da
# revisao feita no BirdNET GUI (clipes classificados como positivos /
# negativos), cruza com o manifesto_clipes.csv gerado por
# extrair_clipes_validacao.R e produz:
#
#   1. validacao_por_clipe.csv   - manifesto + veredito de cada clipe
#   2. precisao_por_faixa.csv    - precisao por especie x faixa de confidence
#   3. thresholds_sugeridos.csv  - menor confidence com precisao acumulada
#                                  >= alvo, por especie
#   4. presenca_por_noite.csv    - local x especie x noite: presenca
#                                  confirmada (tabela para a Daiene)
#   5. clipes_para_retreino.csv  - positivos prontos para o retreino (V2)
#   6. precisao_por_faixa.png    - curva de precisao por especie
#
# Como o BirdNET GUI organiza a revisao movendo os wav para subpastas
# (ex.: <especie>/Positive e <especie>/Negative), o script classifica cada
# clipe pelo caminho em que foi encontrado. Se a sua versao do GUI usar
# outros nomes de pasta, ajuste padrao_positivo / padrao_negativo abaixo.
# Clipes ainda na pasta da especie (fora de Positive/Negative) contam como
# nao validados.
#
# Dependencias: dplyr, readr, stringr, tidyr, ggplot2
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(tidyr)
  library(ggplot2)
})

# -----------------------------------------------------------------------------
# 1. CONFIGURACAO -- edite apenas este bloco
# -----------------------------------------------------------------------------

config <- list(
  # Pasta com os clipes JA REVISADOS no BirdNET GUI (a pasta 'clipes' do
  # pacote de validacao, depois da revisao)
  dir_validado      = "E:/validacao_UEMS_meta4000/clipes",

  # Manifesto gerado na extracao (mesma rodada dos clipes revisados!)
  caminho_manifesto = "E:/validacao_UEMS_meta4000/manifesto_clipes.csv",

  # Onde salvar os resultados
  dir_saida         = "E:/validacao_UEMS_meta4000/resultados",

  # Como reconhecer o veredito pelo caminho do clipe (regex,
  # caixa-insensitivo, aplicado as subpastas onde o wav esta)
  padrao_positivo   = "positiv",   # Positive, positivos, ...
  padrao_negativo   = "negativ",   # Negative, negativos, ...

  # Faixas de confidence para a curva de precisao
  faixas            = seq(0.1, 1, by = 0.1),

  # Precisao-alvo para sugerir o threshold operacional por especie
  precisao_alvo     = 0.90,

  # Minimo de clipes validados numa faixa/corte para o numero ser levado
  # a serio (faixas com menos que isso ficam marcadas como pouco suporte)
  n_minimo          = 15
)

# -----------------------------------------------------------------------------
# 2. LER MANIFESTO E CLASSIFICAR OS CLIPES REVISADOS
# -----------------------------------------------------------------------------

manifesto <- read_csv(config$caminho_manifesto, show_col_types = FALSE)
# manifestos antigos nao tem a coluna 'noite'
if (!"noite" %in% names(manifesto)) manifesto$noite <- manifesto$data_gravacao

wavs <- list.files(config$dir_validado, pattern = "\\.wav$",
                   recursive = TRUE, full.names = TRUE)
if (length(wavs) == 0) stop("Nenhum .wav encontrado em ", config$dir_validado)

revisao <- tibble(caminho_wav = wavs) |>
  mutate(
    arquivo_clipe = basename(caminho_wav),
    subpasta      = str_to_lower(dirname(caminho_wav)),
    veredito      = case_when(
      str_detect(subpasta, regex(config$padrao_positivo)) ~ "positivo",
      str_detect(subpasta, regex(config$padrao_negativo)) ~ "negativo",
      .default = "nao_validado"
    )
  )

resultado <- manifesto |>
  left_join(select(revisao, arquivo_clipe, veredito, caminho_wav),
            by = "arquivo_clipe") |>
  mutate(veredito = replace_na(veredito, "clipe_ausente"))

message("Clipes no manifesto: ", nrow(manifesto))
print(count(resultado, veredito))
if (any(duplicated(revisao$arquivo_clipe))) {
  warning("Ha nomes de clipe duplicados na pasta revisada - confira se ",
          "nao ha copias em mais de uma subpasta.")
}

dir.create(config$dir_saida, recursive = TRUE, showWarnings = FALSE)
write_csv(resultado, file.path(config$dir_saida, "validacao_por_clipe.csv"))

validados <- filter(resultado, veredito %in% c("positivo", "negativo"))
if (nrow(validados) == 0) {
  stop("Nenhum clipe com veredito positivo/negativo - a revisao ja foi ",
       "feita? Confira padrao_positivo/padrao_negativo.")
}

# -----------------------------------------------------------------------------
# 3. PRECISAO POR ESPECIE x FAIXA DE CONFIDENCE
# -----------------------------------------------------------------------------

precisao_faixa <- validados |>
  mutate(faixa = cut(confidence, breaks = config$faixas,
                     include.lowest = TRUE, right = FALSE)) |>
  group_by(local, pasta_especie, faixa) |>
  summarise(n_validados = n(),
            n_positivos = sum(veredito == "positivo"),
            precisao    = n_positivos / n_validados,
            .groups = "drop") |>
  mutate(pouco_suporte = n_validados < config$n_minimo)

write_csv(precisao_faixa,
          file.path(config$dir_saida, "precisao_por_faixa.csv"))

# -----------------------------------------------------------------------------
# 4. THRESHOLD SUGERIDO POR ESPECIE
#    (menor confidence c tal que a precisao entre os clipes validados com
#     confidence >= c atinge a precisao-alvo)
# -----------------------------------------------------------------------------

sugerir_threshold <- function(df, alvo, n_min) {
  cortes <- sort(unique(round(df$confidence, 2)))
  for (c0 in cortes) {
    sub <- filter(df, confidence >= c0)
    if (nrow(sub) >= n_min &&
        mean(sub$veredito == "positivo") >= alvo) {
      return(tibble(threshold = c0,
                    n_suporte = nrow(sub),
                    precisao_no_corte = mean(sub$veredito == "positivo")))
    }
  }
  tibble(threshold = NA_real_, n_suporte = NA_integer_,
         precisao_no_corte = NA_real_)
}

thresholds <- validados |>
  group_by(local, pasta_especie) |>
  group_modify(~ sugerir_threshold(.x, config$precisao_alvo,
                                   config$n_minimo)) |>
  ungroup()

write_csv(thresholds,
          file.path(config$dir_saida, "thresholds_sugeridos.csv"))
message("\nThresholds sugeridos (precisao-alvo ",
        config$precisao_alvo, "):")
print(thresholds, n = 40)

# -----------------------------------------------------------------------------
# 5. PRESENCA CONFIRMADA POR NOITE (tabela para a Daiene)
# -----------------------------------------------------------------------------

presenca_noite <- resultado |>
  group_by(local, pasta_especie, noite) |>
  summarise(
    n_clipes      = n(),
    n_validados   = sum(veredito %in% c("positivo", "negativo")),
    n_positivos   = sum(veredito == "positivo"),
    presenca      = case_when(
      n_positivos > 0 ~ "confirmada",
      n_validados > 0 ~ "nao_detectada_nos_validados",
      .default        = "nao_validada"
    ),
    conf_max_positivo = ifelse(n_positivos > 0,
                               max(confidence[veredito == "positivo"]),
                               NA_real_),
    .groups = "drop"
  )

write_csv(presenca_noite,
          file.path(config$dir_saida, "presenca_por_noite.csv"))

# -----------------------------------------------------------------------------
# 6. CLIPES CONFIRMADOS PARA O RETREINO (V2)
# -----------------------------------------------------------------------------

retreino <- resultado |>
  filter(veredito == "positivo") |>
  select(local, species_code, pasta_especie, arquivo_clipe, caminho_wav,
         confidence, noite, hora_gravacao, audio_origem)

write_csv(retreino,
          file.path(config$dir_saida, "clipes_para_retreino.csv"))
message("\n", nrow(retreino), " clipes positivos listados para o retreino.")

# -----------------------------------------------------------------------------
# 7. CURVA DE PRECISAO (figura)
# -----------------------------------------------------------------------------

g <- precisao_faixa |>
  mutate(conf_meio = config$faixas[as.integer(faixa)] + 0.05) |>
  ggplot(aes(conf_meio, precisao)) +
  geom_hline(yintercept = config$precisao_alvo,
             linetype = "dashed", colour = "grey50") +
  geom_line(colour = "#2a7fbf") +
  geom_point(aes(size = n_validados, alpha = !pouco_suporte),
             colour = "#2a7fbf") +
  scale_alpha_manual(values = c(`TRUE` = 1, `FALSE` = 0.3), guide = "none") +
  scale_size_continuous(name = "clipes validados") +
  scale_x_continuous(limits = c(0.1, 1), breaks = seq(0.1, 1, 0.2)) +
  scale_y_continuous(limits = c(0, 1)) +
  facet_wrap(~ pasta_especie) +
  labs(x = "Confidence (centro da faixa)", y = "Precisao",
       title = "Precisao das predicoes por faixa de confidence",
       subtitle = paste0("Linha tracejada: precisao-alvo (",
                         config$precisao_alvo,
                         "); pontos claros: < ", config$n_minimo,
                         " clipes na faixa")) +
  theme_minimal(base_size = 11)

ggsave(file.path(config$dir_saida, "precisao_por_faixa.png"), g,
       width = 11, height = 8, dpi = 200)

message("\nPronto! Resultados em ", config$dir_saida)
