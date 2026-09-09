# =============================================================================
# extrair_clipes_validacao.R
#
# Gera clipes de audio para validacao manual de predicoes do BirdNET
# (passive acoustic monitoring - projeto FrogNet)
#
# Fluxo (conforme esquema da Larissa):
#   1. Para cada Local, ler a tabela BirdNET_SelectionTable.txt
#      (que concatena as predicoes feitas sobre cada audio do local)
#   2. Para cada Local x Especie x Data+Hora, selecionar as N predicoes
#      com maior confidence score (padrao: 2)
#   3. Mapear cada predicao no audio de origem (coluna Begin Path) e cortar
#      o clipe usando File Offset (s) e a duracao (End Time - Begin Time)
#   4. Nomear o clipe de forma que se possa recuperar local, especie e
#      confidence:  <conf>_<rank>_<nome do arquivo original>_<ini>s_<fim>s.wav
#      e.g. 0.104_1_DIVSPTS01_44p1K_XAR_XAR01_20220111_193000_0.0s_3.0s.wav
#   5. Organizar os clipes em uma pasta por especie (pronto para o
#      BirdNET GUI - aba review)
#   6. Gerar um zip por especie ("pacotes" de validacao) + manifesto .csv
#
# O script e re-executavel: clipes ja existentes nao sao cortados de novo.
#
# Dependencias: dplyr, readr, stringr, purrr, tidyr, av, zip
#   install.packages(c("dplyr", "readr", "stringr", "purrr", "tidyr",
#                      "av", "zip"))
#   (o pacote 'av' ja embute o ffmpeg -- nao precisa instalar nada no sistema)
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
  library(purrr)
  library(tidyr)
})

# -----------------------------------------------------------------------------
# 1. CONFIGURACAO -- edite apenas este bloco
# -----------------------------------------------------------------------------

config <- list(
  # Pasta raiz que contem uma subpasta por Local, cada uma com sua
  # BirdNET_SelectionTable.txt (a busca e recursiva)
  dir_dados     = "N:/Arara",

  # Nome (regex) da tabela de selecao dentro de cada pasta de Local
  padrao_tabela = "^BirdNET_SelectionTable\\.txt$",

  # Pasta de saida (sera criada se nao existir). Estrutura gerada:
  #   <dir_saida>/clipes/<especie>/*.wav
  #   <dir_saida>/pacotes/<especie>.zip
  #   <dir_saida>/manifesto_clipes.csv
  dir_saida     = "N:/Arara/validacao",

  # Quantas predicoes de maior confidence por Local x Especie x Data+Hora
  n_top         = 2,

  # Confidence minima para uma predicao ser candidata (pedido da Larissa,
  # 2026-08-17): sem esse filtro, toda especie acaba com scores bem baixos
  # "no fundo" mesmo quando nao esta presente. NULL = sem filtro.
  conf_minima   = 0.1,

  # Rodar so em alguns locais? Util para o piloto de viabilidade do metodo.
  # NULL = todos os locais. Ex.: locais = c("ARA01")
  locais        = NULL,

  # Janela de datas das gravacoes (AAAAMMDD), ex. a janela do data logger.
  # NULL = sem restricao. Ex.: data_inicio = "20220101", data_fim = "20221231"
  data_inicio   = NULL,
  data_fim      = NULL,

  # Focar em algumas especies (codigos curtos)? NULL = todas.
  # Lista priorizada pela Larissa (e-mail 2026-08-17):
  # especies = c("boa-ran", "boa-pun", "den-min", "den-nan",
  #              "lep-fus", "lep-pod", "phy-alb", "pse-par")
  especies      = NULL,

  # Janela de horas do dia (0-23). Pode cruzar a meia-noite:
  # hora_inicio = 17, hora_fim = 2 pega 17h-23h + 00h-02h. Nesse caso o
  # agrupamento passa a ser por NOITE (a madrugada conta como a noite da
  # vespera), o que mantem cada noite inteira no dia-sim-dia-nao e da as
  # replicas dentro da noite que a Larissa pediu. NULL = sem filtro.
  hora_inicio   = NULL,
  hora_fim      = NULL,

  # "Dia sim, dia nao": mantem noites/dias alternados, ancorado na
  # primeira data de cada local (reprodutivel)
  alternar_dias = FALSE,

  # Meta TOTAL de clipes por local (sugestao da Liliana): a meta e
  # repartida de forma balanceada entre as especies -- especies com menos
  # clipes que a cota entram inteiras e o excedente e redistribuido entre
  # as demais. NULL = sem meta. Ex.: 4000
  meta_total    = NULL,

  # Dentro de cada especie, balancear o sorteio pela hora do dia?
  # (round-robin entre as horas, para cobrir o ciclo diel)
  balancear_por_hora = TRUE,

  # Alternativa mais simples a meta_total: limite fixo de clipes por
  # especie (sorteio reprodutivel). Ignorado se meta_total for definida.
  max_por_especie = NULL,

  # Remapeamento do prefixo dos caminhos da coluna Begin Path.
  # Se o script roda na mesma maquina Windows onde o NAS esta mapeado
  # como N:\, deixe os dois como NULL (os caminhos da tabela funcionam
  # direto). Num Mac/Linux com o NAS montado, use algo como:
  #   remap_de = "N:/", remap_para = "/Volumes/Arara/"
  # (barras normais; o script converte \\ para / antes de remapear)
  remap_de      = NULL,
  remap_para    = NULL,

  # Gerar um .zip por especie ao final?
  fazer_zip     = TRUE,

  # TRUE = so simula (nao corta audio, nao zipa), mas gera o manifesto
  # com tudo que SERIA feito. Util para conferir a selecao antes de rodar.
  simular       = FALSE
)

# -----------------------------------------------------------------------------
# 2. FUNCOES AUXILIARES
# -----------------------------------------------------------------------------

# Le uma BirdNET_SelectionTable.txt (formato Raven, separado por tab) e
# devolve um tibble com nomes de coluna padronizados
ler_tabela_selecao <- function(caminho) {
  tb <- read_tsv(caminho, show_col_types = FALSE,
                 na = c("", "NA"), progress = FALSE)

  # padroniza nomes: minusculas, sem unidades/pontuacao, espacos -> _
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
    stop("Tabela ", caminho, " sem as colunas: ",
         paste(faltando, collapse = ", "),
         "\nColunas encontradas: ", paste(names(tb), collapse = ", "))
  }
  tb
}

# Converte caminhos do estilo Windows (N:\Arara\...) para o formato do
# sistema onde o script roda, aplicando o remapeamento opcional de prefixo
remapear_caminho <- function(caminho, de = NULL, para = NULL) {
  caminho <- str_replace_all(caminho, fixed("\\"), "/")
  if (!is.null(de) && !is.null(para)) {
    de <- str_replace_all(de, fixed("\\"), "/")
    caminho <- str_replace(caminho, fixed(de), para)
  }
  caminho
}

# Extrai data (AAAAMMDD) e hora (HH) do nome do arquivo de gravacao,
# assumindo o padrao <...>_AAAAMMDD_HHMMSS.<ext> dos gravadores
extrair_data_hora <- function(nome_arquivo) {
  m <- str_match(nome_arquivo, "(\\d{8})_(\\d{6})")
  tibble(
    data_gravacao = m[, 2],
    hora_gravacao = str_sub(m[, 3], 1, 2)
  )
}

# Monta o nome do clipe:
#   <conf 3 casas>_<rank>_<arquivo original sem extensao>_<ini>s_<fim>s.wav
nome_clipe <- function(confidence, rank, caminho_audio, ini, fim) {
  base <- tools::file_path_sans_ext(basename(caminho_audio))
  sprintf("%.3f_%d_%s_%.1fs_%.1fs.wav", confidence, rank, base, ini, fim)
}

# Reparte uma meta total entre especies de forma balanceada ("water
# filling"): especies com menos clipes que a cota entram inteiras e o
# excedente e redistribuido entre as que ainda tem sobra
alocar_meta <- function(n_disponivel, meta_total) {
  aloc     <- setNames(integer(length(n_disponivel)), names(n_disponivel))
  restante <- meta_total
  pend     <- names(n_disponivel)
  repeat {
    if (length(pend) == 0 || restante <= 0) break
    cota      <- restante %/% length(pend)
    if (cota == 0) break
    saturadas <- pend[n_disponivel[pend] <= cota]
    if (length(saturadas) == 0) {
      aloc[pend] <- cota
      restante   <- restante - cota * length(pend)
      break
    }
    aloc[saturadas] <- n_disponivel[saturadas]
    restante <- restante - sum(n_disponivel[saturadas])
    pend     <- setdiff(pend, saturadas)
  }
  # distribui a sobra (< 1 por especie) uma a uma
  com_folga <- names(which(aloc < n_disponivel))
  if (restante > 0 && length(com_folga) > 0) {
    extra <- com_folga[seq_len(min(restante, length(com_folga)))]
    aloc[extra] <- aloc[extra] + 1L
  }
  aloc
}

# Sorteia n_alvo clipes de uma especie; com por_hora = TRUE faz um
# round-robin entre as horas do dia (cobre o ciclo diel)
amostrar_clipes <- function(df, n_alvo, por_hora = TRUE) {
  if (nrow(df) <= n_alvo) return(df)
  if (por_hora) {
    df |>
      group_by(hora_gravacao) |>
      mutate(.ordem = sample.int(n())) |>
      ungroup() |>
      arrange(.ordem) |>
      slice_head(n = n_alvo) |>
      select(-.ordem)
  } else {
    slice_sample(df, n = n_alvo)
  }
}

# Corta um clipe com o ffmpeg embutido no pacote 'av'
cortar_clipe <- function(origem, destino, inicio, duracao) {
  av::av_audio_convert(origem, destino,
                       start_time = inicio, total_time = duracao,
                       verbose = FALSE)
}

# -----------------------------------------------------------------------------
# 3. LOCALIZAR E LER AS TABELAS DE CADA LOCAL
# -----------------------------------------------------------------------------

tabelas <- list.files(config$dir_dados, pattern = config$padrao_tabela,
                      recursive = TRUE, full.names = TRUE)
if (length(tabelas) == 0) {
  stop("Nenhuma tabela encontrada em ", config$dir_dados,
       " com o padrao ", config$padrao_tabela)
}
message(length(tabelas), " tabela(s) de selecao encontrada(s):")
walk(tabelas, \(x) message("  - ", x))

# O Local e o nome da pasta que contem a tabela; o prefixo "output_" das
# pastas de saida do BirdNET (ex.: output_UEM -> UEM) e removido
predicoes <- map(tabelas, function(tab) {
  if (file.size(tab) == 0) {
    warning("Tabela vazia ignorada: ", tab)
    return(NULL)
  }
  ler_tabela_selecao(tab) |>
    mutate(local = str_remove(basename(dirname(tab)), "^output_?"),
           .before = 1)
}) |>
  list_rbind()

if (nrow(predicoes) == 0) stop("Nenhuma predicao lida - todas as tabelas ",
                               "encontradas estavam vazias?")

message(nrow(predicoes), " predicoes lidas de ",
        n_distinct(predicoes$local), " local(is).")

# Piloto: restringir aos locais indicados em config$locais
if (!is.null(config$locais)) {
  desconhecidos <- setdiff(config$locais, unique(predicoes$local))
  if (length(desconhecidos) > 0) {
    warning("Local(is) em config$locais sem tabela encontrada: ",
            paste(desconhecidos, collapse = ", "))
  }
  predicoes <- filter(predicoes, local %in% config$locais)
  message("Piloto: processando apenas ",
          paste(intersect(config$locais, unique(predicoes$local)),
                collapse = ", "),
          " (", nrow(predicoes), " predicoes).")
  if (nrow(predicoes) == 0) stop("Nenhuma predicao restante apos o filtro ",
                                 "de locais - confira config$locais.")
}

# -----------------------------------------------------------------------------
# 4. SELECIONAR AS TOP-N POR LOCAL x ESPECIE x DATA+HORA
# -----------------------------------------------------------------------------

selecao <- predicoes |>
  mutate(
    caminho_audio = remapear_caminho(begin_path,
                                     config$remap_de, config$remap_para),
    duracao       = end_time - begin_time,
    inicio_clipe  = file_offset,
    fim_clipe     = file_offset + duracao
  )
selecao <- bind_cols(selecao,
                     extrair_data_hora(basename(selecao$begin_path)))

if (anyNA(selecao$data_gravacao)) {
  n_na <- sum(is.na(selecao$data_gravacao))
  warning(n_na, " predicao(oes) com nome de arquivo sem padrao ",
          "_AAAAMMDD_HHMMSS - agrupadas com data/hora = NA.")
}

selecao <- mutate(selecao,
                  hora_int   = suppressWarnings(as.integer(hora_gravacao)),
                  data_grupo = data_gravacao)

# Filtro de especies (codigos curtos)
if (!is.null(config$especies)) {
  antes   <- nrow(selecao)
  selecao <- filter(selecao,
                    str_extract(species_code, "[^_]+$") %in% config$especies)
  message("Filtro de ", length(config$especies), " especie(s): ", antes,
          " -> ", nrow(selecao), " predicoes.")
  faltantes <- setdiff(config$especies,
                       str_extract(unique(selecao$species_code), "[^_]+$"))
  if (length(faltantes) > 0) {
    warning("Especies pedidas sem nenhuma predicao: ",
            paste(faltantes, collapse = ", "))
  }
  if (nrow(selecao) == 0) stop("Nenhuma predicao das especies pedidas.")
}

# Janela de horas; cruzando a meia-noite, agrupa por NOITE
if (!is.null(config$hora_inicio) && !is.null(config$hora_fim)) {
  antes <- nrow(selecao)
  hi <- config$hora_inicio; hf <- config$hora_fim
  if (hi <= hf) {
    selecao <- filter(selecao, hora_int >= hi, hora_int <= hf)
  } else {
    selecao <- selecao |>
      filter(hora_int >= hi | hora_int <= hf) |>
      mutate(data_grupo = if_else(
        hora_int <= hf,
        format(as.Date(data_gravacao, "%Y%m%d") - 1, "%Y%m%d"),
        data_gravacao))
    message("Janela cruza a meia-noite: agrupando por noite ",
            "(madrugada conta como a noite da vespera).")
  }
  message("Janela de horas ", hi, "h-", hf, "h: ", antes, " -> ",
          nrow(selecao), " predicoes.")
  if (nrow(selecao) == 0) stop("Nenhuma predicao na janela de horas.")
}

# "Dia sim, dia nao" (por local, sobre a data/noite de agrupamento)
if (isTRUE(config$alternar_dias)) {
  antes <- nrow(selecao)
  selecao <- selecao |>
    group_by(local) |>
    mutate(.dia = as.integer(
      as.Date(data_grupo, "%Y%m%d") -
        min(as.Date(data_grupo, "%Y%m%d"), na.rm = TRUE))) |>
    ungroup() |>
    filter(.dia %% 2 == 0) |>
    select(-.dia)
  message("Dia sim, dia nao: ", antes, " -> ", nrow(selecao), " predicoes.")
}

# Janela de datas (ex.: periodo do data logger)
if (!is.null(config$data_inicio) || !is.null(config$data_fim)) {
  antes <- nrow(selecao)
  di <- if (is.null(config$data_inicio)) "00000000" else as.character(config$data_inicio)
  df_ <- if (is.null(config$data_fim))    "99999999" else as.character(config$data_fim)
  selecao <- filter(selecao, !is.na(data_gravacao),
                    data_gravacao >= di, data_gravacao <= df_)
  message("Janela de datas ", di, "-", df_, ": ", antes, " -> ",
          nrow(selecao), " predicoes.")
  if (nrow(selecao) == 0) stop("Nenhuma predicao dentro da janela de datas.")
}

if (!is.null(config$conf_minima)) {
  antes   <- nrow(selecao)
  selecao <- filter(selecao, confidence >= config$conf_minima)
  message(antes - nrow(selecao), " predicoes descartadas pelo filtro de ",
          "confidence < ", config$conf_minima, ".")
}

selecao <- selecao |>
  group_by(local, species_code, data_grupo, hora_gravacao) |>
  arrange(desc(confidence), .by_group = TRUE) |>
  slice_head(n = config$n_top) |>
  mutate(rank = row_number()) |>
  ungroup() |>
  mutate(
    # usa so o codigo curto da especie (parte final do rotulo do
    # classificador, ex. "Adenomera diptyx_ade-dip" -> "ade_dip");
    # se o rotulo ja for curto ("ade-dip"), funciona igual
    pasta_especie = str_replace_all(str_extract(species_code, "[^_]+$"),
                                    "-", "_"),
    arquivo_clipe = nome_clipe(confidence, rank, caminho_audio,
                               inicio_clipe, fim_clipe)
  )

message(nrow(selecao), " clipes selecionados (top ", config$n_top,
        " por local x especie x data+hora) de ",
        n_distinct(selecao$species_code), " especie(s).")

# Meta total balanceada por especie (e, opcionalmente, por hora), ou
# limite fixo por especie -- sorteios reprodutiveis (seed fixa)
if (!is.null(config$meta_total)) {
  if (!is.null(config$max_por_especie)) {
    warning("meta_total definida - max_por_especie sera ignorado.")
  }
  antes <- nrow(selecao)
  set.seed(2026)
  selecao <- selecao |>
    group_split(local) |>
    map(function(sel_local) {
      n_disp <- table(sel_local$species_code)
      aloc   <- alocar_meta(setNames(as.integer(n_disp), names(n_disp)),
                            config$meta_total)
      sel_local |>
        group_split(species_code) |>
        map(\(df) amostrar_clipes(df, aloc[[df$species_code[1]]],
                                  config$balancear_por_hora)) |>
        list_rbind()
    }) |>
    list_rbind()
  message("Meta de ", config$meta_total, " clipes por local (balanceada ",
          "por especie", if (config$balancear_por_hora) " e hora", "): ",
          antes, " -> ", nrow(selecao), " clipes.")
} else if (!is.null(config$max_por_especie)) {
  antes <- nrow(selecao)
  set.seed(2026)
  selecao <- selecao |>
    group_split(local, species_code) |>
    map(\(df) amostrar_clipes(df, config$max_por_especie,
                              config$balancear_por_hora)) |>
    list_rbind()
  message("Limite de ", config$max_por_especie, " clipes por especie ",
          "(por local): ", antes, " -> ", nrow(selecao), " clipes.")
}

# -----------------------------------------------------------------------------
# 5. CORTAR OS CLIPES (uma pasta por especie)
# -----------------------------------------------------------------------------

dir_clipes <- file.path(config$dir_saida, "clipes")
dir.create(dir_clipes, recursive = TRUE, showWarnings = FALSE)

selecao <- selecao |>
  mutate(destino = file.path(dir_clipes, pasta_especie, arquivo_clipe))

walk(unique(dirname(selecao$destino)),
     dir.create, recursive = TRUE, showWarnings = FALSE)

processar_linha <- function(origem, destino, inicio, duracao) {
  if (file.exists(destino))       return("ja_existia")
  if (!file.exists(origem))       return("audio_nao_encontrado")
  if (config$simular)             return("simulado")
  resultado <- tryCatch({
    cortar_clipe(origem, destino, inicio, duracao)
    "ok"
  }, error = function(e) paste0("erro: ", conditionMessage(e)))
  resultado
}

message(if (config$simular) "Simulando corte de " else "Cortando ",
        nrow(selecao), " clipes...")

selecao$status <- pmap_chr(
  list(selecao$caminho_audio, selecao$destino,
       selecao$inicio_clipe, selecao$duracao),
  processar_linha,
  .progress = "clipes"
)

print(count(selecao, status))
if (any(str_starts(selecao$status, "erro|audio_nao"))) {
  warning("Alguns clipes nao foram gerados - confira a coluna 'status' ",
          "do manifesto e o remapeamento de caminhos (remap_de/remap_para).")
}

# -----------------------------------------------------------------------------
# 6. MANIFESTO
# -----------------------------------------------------------------------------

manifesto <- selecao |>
  select(local, species_code, pasta_especie, data_gravacao,
         noite = data_grupo, hora_gravacao,
         rank, confidence, arquivo_clipe, inicio_clipe, fim_clipe, duracao,
         audio_origem = caminho_audio, begin_path_original = begin_path,
         status)

caminho_manifesto <- file.path(config$dir_saida, "manifesto_clipes.csv")
write_csv(manifesto, caminho_manifesto)
message("Manifesto salvo em ", caminho_manifesto)

# -----------------------------------------------------------------------------
# 7. PACOTES DE VALIDACAO (um zip por especie)
# -----------------------------------------------------------------------------

if (config$fazer_zip && !config$simular) {
  dir_pacotes <- file.path(config$dir_saida, "pacotes")
  dir.create(dir_pacotes, recursive = TRUE, showWarnings = FALSE)

  especies <- sort(unique(selecao$pasta_especie))
  for (sp in especies) {
    zip_sp <- file.path(dir_pacotes, paste0(sp, ".zip"))
    zip::zip(zipfile = zip_sp, files = sp, root = dir_clipes,
             mode = "mirror")
    message("Pacote ", basename(zip_sp), ": ",
            round(file.size(zip_sp) / 1024^2, 1), " MB")
  }
  message(length(especies), " pacote(s) de validacao em ", dir_pacotes)
}

message("Pronto! Os clipes em ", dir_clipes,
        " estao prontos para validacao no BirdNET GUI (review).")
