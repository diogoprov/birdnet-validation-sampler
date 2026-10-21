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
#      com maior confidence score (padrao: 2). Para estimar taxas de falsos
#      positivos ha dois modos aleatorios (config$modo_amostragem): sorteio
#      de ocasioes com deteccao ou de gravacoes entre todas as gravadas
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

  # Como escolher o que vai para a validacao:
  #   "top"                 - as n_top predicoes de maior confidence por
  #                           Local x Especie x Data+Hora (padrao; serve ao
  #                           retreino e a calibracao score -> P(TP))
  #   "aleatorio_deteccoes" - sorteio de OCASIOES com >= 1 predicao da
  #                           especie com confidence >= limiar; corta TODAS
  #                           as predicoes >= limiar da ocasiao sorteada
  #                           (Chambert et al. 2015)
  #   "aleatorio_gravacoes" - sorteio de gravacoes/minutos entre TODOS os
  #                           gravados, com ou sem predicao, para anotacao
  #                           por ouvido (Miller et al. 2011)
  # Para estimar taxas de falsos positivos (ex. crywolf), NAO use "top".
  modo_amostragem = "top",

  # Ocasiao = unidade que entra no modelo de ocupacao: "arquivo" (a
  # gravacao inteira) ou "minuto" (minuto do arquivo, via File Offset)
  unidade_ocasiao = "arquivo",

  # Limiar de confidence da analise de ocupacao (o mesmo que sera usado
  # la!). Define as ocasioes candidatas em "aleatorio_deteccoes" e a
  # contagem n_deteccoes_ocasiao do manifesto. NULL = nao conta.
  limiar        = NULL,

  # "top": quantas predicoes de maior confidence por Local x Especie x
  # Data+Hora. "aleatorio_deteccoes": quantas OCASIOES sorteadas por
  # Local x Especie x Data+Hora.
  n_top         = 2,

  # "aleatorio_gravacoes": fracao das gravacoes (ou minutos) sorteada em
  # cada local -- proporcional ao esforco. n_gravacoes_por_local, se
  # definido, fixa um numero por local no lugar da fracao.
  fracao_gravacoes      = 0.01,
  n_gravacoes_por_local = NULL,

  # "aleatorio_gravacoes": de onde vem a lista de TODAS as gravacoes.
  # NULL = list.files() nas pastas de audio que aparecem na coluna Begin
  # Path (pastas sem nenhuma predicao ficam de fora!). Ou o caminho de um
  # .csv com as colunas local e caminho_audio.
  tabela_gravacoes = NULL,
  padrao_audio     = "\\.(wav|flac|mp3)$",

  # Duracao das gravacoes (s), para unidade_ocasiao = "minuto" em
  # "aleatorio_gravacoes" e para o fim_clipe das gravacoes inteiras.
  # NULL = le de cada arquivo com av::av_media_info() quando precisar.
  duracao_gravacao = NULL,

  # Confidence minima para uma predicao ser candidata no modo "top"
  # (pedido da Larissa, 2026-08-17): sem esse filtro, toda especie acaba
  # com scores bem baixos "no fundo" mesmo quando nao esta presente.
  # NULL = sem filtro. Nos modos aleatorios vale o 'limiar'.
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
  # Em "aleatorio_deteccoes" a meta conta OCASIOES (cada uma vira todos os
  # seus clipes); em "aleatorio_gravacoes" e ignorada (vale a fracao).
  meta_total    = NULL,

  # Dentro de cada especie, balancear o sorteio pela hora do dia?
  # (round-robin entre as horas, para cobrir o ciclo diel)
  balancear_por_hora = TRUE,

  # Alternativa mais simples a meta_total: limite fixo de clipes por
  # especie (sorteio reprodutivel). Ignorado se meta_total for definida.
  # Em "aleatorio_deteccoes" conta ocasioes, como meta_total.
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

# Codigo curto da especie para nome de pasta: parte final do rotulo do
# classificador, ex. "Adenomera diptyx_ade-dip" -> "ade_dip"; se o rotulo
# ja for curto ("ade-dip"), funciona igual
pasta_da_especie <- function(species_code) {
  str_replace_all(str_extract(species_code, "[^_]+$"), "-", "_")
}

# Identificador da ocasiao: o arquivo (sem extensao) ou arquivo + minuto
id_ocasiao <- function(caminho_audio, inicio, unidade) {
  base <- tools::file_path_sans_ext(basename(caminho_audio))
  if (unidade == "minuto") {
    sprintf("%s_m%03d", base, as.integer(inicio %/% 60))
  } else {
    base
  }
}

# Duracao (s) de cada gravacao: config$duracao_gravacao ou lida do arquivo
duracao_audio <- function(caminhos, fixa = NULL) {
  if (!is.null(fixa)) return(rep(fixa, length(caminhos)))
  map_dbl(caminhos, \(f) tryCatch(av::av_media_info(f)$duration,
                                  error = function(e) NA_real_))
}

# Filtros de tempo (janela de horas, dia sim/dia nao, janela de datas),
# sobre uma tabela com local, data_gravacao, hora_int e data_grupo
filtrar_tempo <- function(df, rotulo = "predicoes") {
  # Janela de horas; cruzando a meia-noite, agrupa por NOITE
  if (!is.null(config$hora_inicio) && !is.null(config$hora_fim)) {
    antes <- nrow(df)
    hi <- config$hora_inicio; hf <- config$hora_fim
    if (hi <= hf) {
      df <- filter(df, hora_int >= hi, hora_int <= hf)
    } else {
      df <- df |>
        filter(hora_int >= hi | hora_int <= hf) |>
        mutate(data_grupo = if_else(
          hora_int <= hf,
          format(as.Date(data_gravacao, "%Y%m%d") - 1, "%Y%m%d"),
          data_gravacao))
      message("Janela cruza a meia-noite: agrupando por noite ",
              "(madrugada conta como a noite da vespera).")
    }
    message("Janela de horas ", hi, "h-", hf, "h: ", antes, " -> ",
            nrow(df), " ", rotulo, ".")
    if (nrow(df) == 0) stop("Nenhuma linha (", rotulo, ") na janela de horas.")
  }

  # "Dia sim, dia nao" (por local, sobre a data/noite de agrupamento)
  if (isTRUE(config$alternar_dias)) {
    antes <- nrow(df)
    df <- df |>
      group_by(local) |>
      mutate(.dia = as.integer(
        as.Date(data_grupo, "%Y%m%d") -
          min(as.Date(data_grupo, "%Y%m%d"), na.rm = TRUE))) |>
      ungroup() |>
      filter(.dia %% 2 == 0) |>
      select(-.dia)
    message("Dia sim, dia nao: ", antes, " -> ", nrow(df), " ", rotulo, ".")
  }

  # Janela de datas (ex.: periodo do data logger)
  if (!is.null(config$data_inicio) || !is.null(config$data_fim)) {
    antes <- nrow(df)
    di <- if (is.null(config$data_inicio)) "00000000" else as.character(config$data_inicio)
    df_ <- if (is.null(config$data_fim))    "99999999" else as.character(config$data_fim)
    df <- filter(df, !is.na(data_gravacao),
                 data_gravacao >= di, data_gravacao <= df_)
    message("Janela de datas ", di, "-", df_, ": ", antes, " -> ",
            nrow(df), " ", rotulo, ".")
    if (nrow(df) == 0) stop("Nenhuma linha (", rotulo, ") dentro da janela de datas.")
  }
  df
}

# Corta um clipe com o ffmpeg embutido no pacote 'av' (duracao NA = ate o
# fim do arquivo)
cortar_clipe <- function(origem, destino, inicio, duracao) {
  av::av_audio_convert(origem, destino,
                       start_time = inicio,
                       total_time = if (is.na(duracao)) NULL else duracao,
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
# 4. SELECIONAR (top-N, ocasioes sorteadas ou gravacoes sorteadas)
# -----------------------------------------------------------------------------

modo <- match.arg(config$modo_amostragem,
                  c("top", "aleatorio_deteccoes", "aleatorio_gravacoes"))
unidade <- match.arg(config$unidade_ocasiao, c("arquivo", "minuto"))
if (modo == "aleatorio_deteccoes" && is.null(config$limiar)) {
  stop("modo_amostragem = \"aleatorio_deteccoes\" exige config$limiar ",
       "(o mesmo limiar de confidence da analise de ocupacao).")
}
message("Modo de amostragem: ", modo, " (ocasiao = ", unidade, ").")

selecao <- predicoes |>
  mutate(
    caminho_audio = remapear_caminho(begin_path,
                                     config$remap_de, config$remap_para),
    duracao       = end_time - begin_time,
    inicio_clipe  = file_offset,
    fim_clipe     = file_offset + duracao,
    ocasiao_id    = id_ocasiao(caminho_audio, file_offset, unidade)
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

# Lista de TODAS as gravacoes (so no modo "aleatorio_gravacoes"); o
# default sao as pastas de audio que aparecem nas tabelas de selecao
if (modo == "aleatorio_gravacoes") {
  if (!is.null(config$tabela_gravacoes)) {
    gravacoes <- read_csv(config$tabela_gravacoes, show_col_types = FALSE) |>
      transmute(local, caminho_audio = remapear_caminho(
        caminho_audio, config$remap_de, config$remap_para))
  } else {
    gravacoes <- selecao |>
      distinct(local, pasta = dirname(caminho_audio)) |>
      mutate(caminho_audio = map(pasta, \(d) list.files(
        d, pattern = config$padrao_audio, full.names = TRUE,
        ignore.case = TRUE))) |>
      unnest(caminho_audio) |>
      distinct(local, caminho_audio)
  }
  if (nrow(gravacoes) == 0) stop("Nenhuma gravacao encontrada - confira ",
                                 "remap_de/remap_para ou tabela_gravacoes.")
  gravacoes <- bind_cols(gravacoes,
                         extrair_data_hora(basename(gravacoes$caminho_audio))) |>
    mutate(hora_int   = suppressWarnings(as.integer(hora_gravacao)),
           data_grupo = data_gravacao)
  message(nrow(gravacoes), " gravacoes listadas em ",
          n_distinct(gravacoes$local), " local(is).")
}

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

# Especies a anotar no modo "aleatorio_gravacoes" (antes dos filtros de
# tempo: a especie entra mesmo sem predicao na janela). Cada gravacao
# sorteada e copiada uma vez por especie -- restrinja com config$especies
especies_alvo <- sort(unique(selecao$species_code))

selecao <- filtrar_tempo(selecao, "predicoes")

# Predicoes da especie >= limiar por ocasiao (para conferir que todas as
# deteccoes de uma ocasiao checada foram cortadas)
n_det_ocasiao <- if (!is.null(config$limiar)) {
  selecao |>
    filter(confidence >= config$limiar) |>
    count(local, species_code, ocasiao_id, name = "n_deteccoes_ocasiao")
}

if (modo == "top") {
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
      pasta_especie = pasta_da_especie(species_code),
      arquivo_clipe = nome_clipe(confidence, rank, caminho_audio,
                                 inicio_clipe, fim_clipe),
      # selecao pelo score: nao e uma amostra probabilistica
      prob_inclusao = NA_real_
    )

  message(nrow(selecao), " clipes selecionados (top ", config$n_top,
          " por local x especie x data+hora) de ",
          n_distinct(selecao$species_code), " especie(s).")
} else if (modo == "aleatorio_deteccoes") {
  # Candidatas: ocasioes com >= 1 predicao da especie >= limiar. O sorteio
  # (n_top ocasioes por local x especie x data+hora) nao olha o score.
  deteccoes <- filter(selecao, confidence >= config$limiar)
  set.seed(2026)
  selecao <- deteccoes |>
    distinct(local, species_code, ocasiao_id,
             data_gravacao, data_grupo, hora_gravacao) |>
    group_by(local, species_code, data_grupo, hora_gravacao) |>
    mutate(.p1 = min(config$n_top, n()) / n()) |>
    slice_sample(n = config$n_top) |>
    ungroup()
  message(nrow(selecao), " ocasioes sorteadas (", config$n_top,
          " por local x especie x data+hora) entre ",
          n_distinct(deteccoes[c("local", "species_code", "ocasiao_id")]),
          " com predicao >= ", config$limiar, ".")
  ocasioes_candidatas <- selecao
} else {
  # Sorteio entre TODAS as gravacoes (ou minutos), com ou sem predicao,
  # proporcional ao esforco de cada local
  gravacoes <- filtrar_tempo(gravacoes, "gravacoes")
  if (unidade == "minuto") {
    gravacoes <- gravacoes |>
      mutate(.dur = duracao_audio(caminho_audio, config$duracao_gravacao))
    if (anyNA(gravacoes$.dur)) {
      warning(sum(is.na(gravacoes$.dur)), " gravacao(oes) sem duracao ",
              "legivel - ignoradas. Defina config$duracao_gravacao?")
    }
    gravacoes <- gravacoes |>
      filter(!is.na(.dur)) |>
      mutate(inicio_clipe = map(.dur, \(d) (seq_len(ceiling(d / 60)) - 1) * 60)) |>
      unnest(inicio_clipe) |>
      mutate(fim_clipe = pmin(inicio_clipe + 60, .dur)) |>
      select(-.dur)
  } else {
    gravacoes <- gravacoes |>
      mutate(inicio_clipe = 0,
             fim_clipe    = if (is.null(config$duracao_gravacao)) NA_real_
                            else config$duracao_gravacao)
  }
  gravacoes <- mutate(gravacoes,
                      ocasiao_id = id_ocasiao(caminho_audio, inicio_clipe,
                                              unidade))

  set.seed(2026)
  sorteadas <- gravacoes |>
    group_split(local) |>
    map(function(g) {
      n_alvo <- if (!is.null(config$n_gravacoes_por_local)) {
        min(config$n_gravacoes_por_local, nrow(g))
      } else {
        max(1, round(config$fracao_gravacoes * nrow(g)))
      }
      slice_sample(g, n = n_alvo) |>
        mutate(prob_inclusao = n_alvo / nrow(g))
    }) |>
    list_rbind()
  message(nrow(sorteadas), " ", unidade, "(s) sorteado(s) entre ",
          nrow(gravacoes), " gravado(s), para anotar ",
          length(especies_alvo), " especie(s).")

  # Uma copia da gravacao/minuto por especie a anotar (o veredito e por
  # especie, na pasta da especie)
  selecao <- sorteadas |>
    cross_join(tibble(species_code = especies_alvo)) |>
    mutate(
      begin_path    = caminho_audio,
      confidence    = NA_real_,
      rank          = NA_integer_,
      duracao       = fim_clipe - inicio_clipe,
      pasta_especie = pasta_da_especie(species_code),
      arquivo_clipe = paste0("grav_", local, "_", pasta_especie, "_",
                             ocasiao_id, ".wav")
    )
}

# Meta total balanceada por especie (e, opcionalmente, por hora), ou
# limite fixo por especie -- sorteios reprodutiveis (seed fixa). Em
# "aleatorio_deteccoes" as unidades sorteadas sao ocasioes.
unid <- if (modo == "aleatorio_deteccoes") "ocasioes" else "clipes"
if (modo == "aleatorio_gravacoes" &&
    (!is.null(config$meta_total) || !is.null(config$max_por_especie))) {
  warning("meta_total/max_por_especie ignorados em \"aleatorio_gravacoes\" ",
          "(vale fracao_gravacoes ou n_gravacoes_por_local).")
} else if (!is.null(config$meta_total)) {
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
  message("Meta de ", config$meta_total, " ", unid, " por local (balanceada ",
          "por especie", if (config$balancear_por_hora) " e hora", "): ",
          antes, " -> ", nrow(selecao), " ", unid, ".")
} else if (!is.null(config$max_por_especie)) {
  antes <- nrow(selecao)
  set.seed(2026)
  selecao <- selecao |>
    group_split(local, species_code) |>
    map(\(df) amostrar_clipes(df, config$max_por_especie,
                              config$balancear_por_hora)) |>
    list_rbind()
  message("Limite de ", config$max_por_especie, " ", unid, " por especie ",
          "(por local): ", antes, " -> ", nrow(selecao), " ", unid, ".")
}

if (modo == "aleatorio_deteccoes") {
  # Probabilidade de inclusao = sorteio por data+hora (.p1) x sorteio da
  # meta/limite. A alocacao da meta e deterministica dado o numero de
  # candidatas, entao a 2a etapa e n/N no estrato (local x especie, x hora
  # se balancear_por_hora)
  usou_meta <- !is.null(config$meta_total) || !is.null(config$max_por_especie)
  estrato   <- c("local", "species_code",
                 if (usou_meta && config$balancear_por_hora) "hora_gravacao")
  p2 <- if (usou_meta) {
    inner_join(count(selecao, across(all_of(estrato)), name = ".n"),
               count(ocasioes_candidatas, across(all_of(estrato)), name = ".N"),
               by = estrato) |>
      mutate(.p2 = .n / .N) |>
      select(all_of(estrato), .p2)
  } else {
    distinct(selecao, across(all_of(estrato))) |> mutate(.p2 = 1)
  }

  # Cada ocasiao sorteada vira TODAS as suas predicoes >= limiar
  selecao <- selecao |>
    left_join(p2, by = estrato) |>
    transmute(local, species_code, ocasiao_id, prob_inclusao = .p1 * .p2) |>
    inner_join(deteccoes, by = c("local", "species_code", "ocasiao_id"),
               relationship = "one-to-many") |>
    group_by(local, species_code, ocasiao_id) |>
    arrange(file_offset, .by_group = TRUE) |>
    mutate(rank = row_number()) |>
    ungroup() |>
    mutate(pasta_especie = pasta_da_especie(species_code),
           arquivo_clipe = nome_clipe(confidence, rank, caminho_audio,
                                      inicio_clipe, fim_clipe))
  message(nrow(selecao), " clipes (todas as predicoes >= ", config$limiar,
          " das ", n_distinct(selecao[c("local", "species_code",
                                        "ocasiao_id")]),
          " ocasioes sorteadas).")
}

selecao <- mutate(selecao, modo_amostragem = modo)
if (!is.null(n_det_ocasiao)) {
  selecao <- selecao |>
    left_join(n_det_ocasiao, by = c("local", "species_code", "ocasiao_id")) |>
    mutate(n_deteccoes_ocasiao = replace_na(n_deteccoes_ocasiao, 0L))
} else {
  selecao$n_deteccoes_ocasiao <- NA_integer_
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
         status, modo_amostragem, ocasiao_id, n_deteccoes_ocasiao,
         prob_inclusao)

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
