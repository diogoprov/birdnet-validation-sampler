# =============================================================================
# gerar_matrizes_comunidade.R
#
# Gera matrizes de comunidade (local x mes) a partir do historico de deteccao
# calibrado (saida de calibracao.R), para uso em ordenacoes multivariadas.
#
# Racional:
#   - Como as analises downstream (PCoA/NMDS/RDA) nao modelam falsos positivos,
#     a regra de entrada e RIGIDA: uma especie so conta como detectada numa
#     noite se houve >= k_min deteccoes com P(TP) calibrada >= p_min naquela
#     noite (coluna deteccao_k2 do historico, para k_min = 2).
#   - Apenas as especies-nucleo (calibracao confiavel em todos os locais)
#     entram na matriz; as demais criariam beta-diversidade artefatual por
#     diferenca de recall do classificador entre locais.
#   - O valor da celula e a FREQUENCIA de noites-com-deteccao padronizada
#     pelo esforco: n noites com deteccao / n noites gravadas naquele
#     local x mes. Isso corrige o esforco desigual entre locais (inicios de
#     gravacao diferentes, falhas de gravador).
#   - Esforco (noites gravadas) e aproximado pelo n. de noites distintas que
#     aparecem no historico para o local (qualquer especie, qualquer
#     confidence >= 0.1): com ~2.500 deteccoes/noite na base completa,
#     toda noite efetivamente gravada aparece no historico.
#
# Uso: ajuste o bloco `config` e rode o script inteiro.
# Dependencias: tidyverse (dplyr, tidyr, readr, stringr)
# =============================================================================

library(dplyr)
library(tidyr)
library(readr)
library(stringr)

# --------------------------------------------------------------------------
# config
# --------------------------------------------------------------------------
config <- list(
  # pasta do projeto (a mesma de calibracao.R)
  dir_projeto = "~/Library/CloudStorage/Box-Box/Meus Artigos/2026-codigo FrogNet",

  # historico de deteccao por noite (saida de calibracao.R)
  arquivo_historico = "calibracao/historico_deteccao_noite.csv",

  # pasta de saida (criada se nao existir)
  dir_saida = "matrizes_comunidade",

  # regra de repeticao: 1, 2 ou 3 deteccoes confiaveis (P(TP) >= 0.95) na noite
  k_min = 2,

  # especies-nucleo: calibracao confiavel em todos os locais
  # (as 6 problematicas -- tra_typ, boa_pun, den_min, sci_fuv, ade_dip,
  #  lep_ele -- ficam FORA; use-as no maximo em analise de sensibilidade)
  especies_nucleo = c("boa_ran", "den_nan", "phy_alb", "rhi_dip", "sci_nas",
                      "lep_pod", "lep_fus", "pse_par", "pit_azu", "lys_lim"),

  # esforco minimo: local x mes com menos noites gravadas que isso e
  # descartado da matriz (frequencias instaveis); os descartados sao
  # listados em esforco_local_mes.csv (coluna incluido)
  min_noites_mes = 5
)

# --------------------------------------------------------------------------
# leitura
# --------------------------------------------------------------------------
dir_projeto <- path.expand(config$dir_projeto)
caminho_hist <- file.path(dir_projeto, config$arquivo_historico)
stopifnot("historico nao encontrado" = file.exists(caminho_hist))

historico <- read_csv(
  caminho_hist,
  col_types = cols(noite = col_character(), .default = col_guess())
)

col_k <- paste0("deteccao_k", config$k_min)
stopifnot("coluna da regra k nao existe no historico" =
            col_k %in% names(historico))

faltantes <- setdiff(config$especies_nucleo, unique(historico$especie))
if (length(faltantes) > 0) {
  warning("Especies-nucleo ausentes do historico: ",
          paste(faltantes, collapse = ", "))
}

# --------------------------------------------------------------------------
# esforco: noites gravadas por local x mes
# (todas as especies e todas as deteccoes contam para definir se a noite
#  foi gravada -- nao so as especies-nucleo)
# --------------------------------------------------------------------------
historico <- historico |>
  mutate(mes = str_c(str_sub(noite, 1, 4), "-", str_sub(noite, 5, 6)))

esforco <- historico |>
  distinct(local, mes, noite) |>
  count(local, mes, name = "n_noites_gravadas") |>
  mutate(incluido = n_noites_gravadas >= config$min_noites_mes)

# --------------------------------------------------------------------------
# noites-com-deteccao por local x mes x especie (regra k_min, so nucleo)
# --------------------------------------------------------------------------
deteccoes <- historico |>
  filter(especie %in% config$especies_nucleo,
         .data[[col_k]] == 1) |>
  count(local, mes, especie, name = "n_noites_deteccao")

longo <- esforco |>
  filter(incluido) |>
  select(local, mes, n_noites_gravadas) |>
  crossing(especie = config$especies_nucleo) |>
  left_join(deteccoes, by = c("local", "mes", "especie")) |>
  mutate(
    n_noites_deteccao = replace_na(n_noites_deteccao, 0L),
    frequencia = n_noites_deteccao / n_noites_gravadas
  )

# --------------------------------------------------------------------------
# matrizes largas (linhas = local x mes; colunas = especies)
# --------------------------------------------------------------------------
matriz_freq <- longo |>
  select(local, mes, n_noites_gravadas, especie, frequencia) |>
  pivot_wider(names_from = especie, values_from = frequencia) |>
  arrange(local, mes)

matriz_cont <- longo |>
  select(local, mes, n_noites_gravadas, especie, n_noites_deteccao) |>
  pivot_wider(names_from = especie, values_from = n_noites_deteccao) |>
  arrange(local, mes)

# --------------------------------------------------------------------------
# saida
# --------------------------------------------------------------------------
dir_saida <- file.path(dir_projeto, config$dir_saida)
dir.create(dir_saida, showWarnings = FALSE, recursive = TRUE)

sufixo <- paste0("local_mes_k", config$k_min)
write_csv(matriz_freq,
          file.path(dir_saida, paste0("matriz_frequencia_", sufixo, ".csv")))
write_csv(matriz_cont,
          file.path(dir_saida, paste0("matriz_contagens_", sufixo, ".csv")))
write_csv(esforco,
          file.path(dir_saida, "esforco_local_mes.csv"))

# --------------------------------------------------------------------------
# resumo no console
# --------------------------------------------------------------------------
n_desc <- sum(!esforco$incluido)
message("Matriz: ", nrow(matriz_freq), " linhas (local x mes) x ",
        length(config$especies_nucleo), " especies | regra k >= ",
        config$k_min, ", P(TP) >= 0.95")
message("Esforco: ", sum(esforco$incluido), " celulas local x mes incluidas; ",
        n_desc, " descartadas por terem < ", config$min_noites_mes,
        " noites gravadas (ver esforco_local_mes.csv)")
message("Arquivos em: ", dir_saida)

matriz_freq |>
  group_by(local) |>
  summarise(meses = n(),
            noites = sum(n_noites_gravadas),
            .groups = "drop") |>
  print(n = Inf)
