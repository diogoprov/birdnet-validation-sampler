# Dados simulados pequenos para os testes e para gerar as saidas de
# referencia da v1.2.0 (data-raw/make_reference_v1.2.0.R). So R base + withr,
# para servir tanto aos scripts antigos quanto ao pacote.

sim_especies <- c("Boana raniceps_boa-ran", "Dendropsophus nanus_den-nan",
                  "Scinax nasicus_sci-nas")

# Prefixo Windows usado nas colunas Begin Path (remapeado para a raiz)
sim_prefixo <- "N:\\Arara\\"

# Cria em <raiz>:
#   audio/<LOCAL>/<LOCAL>01_AAAAMMDD_HHMMSS.wav   (arquivos vazios)
#   tabelas/output_ARA/BirdNET_SelectionTable.txt  (formato Raven)
#   tabelas/output_XAR/..., tabelas/BAI/...
# Cada gravacao tem 180 s; algumas nao tem nenhuma predicao.
# Os caminhos de Begin Path comecam por sim_prefixo (remap_from = "N:/Arara/").
# Devolve (invisivel) as predicoes simuladas.
simulate_pam <- function(raiz, semente = 1) {
  withr::with_seed(semente, {
    locais <- c(ARA = "output_ARA", XAR = "output_XAR", BAI = "BAI")
    datas  <- format(as.Date("2022-01-10") + 0:6, "%Y%m%d")
    # duas gravacoes na hora 18 (estrato com mais de uma ocasiao)
    horas  <- c("120000", "180000", "184500", "193000", "220000", "000000",
                "013000", "030000")
    out <- list()
    for (loc in names(locais)) {
      dir_audio <- file.path(raiz, "audio", loc)
      dir.create(dir_audio, recursive = TRUE, showWarnings = FALSE)
      arquivos <- as.vector(outer(datas, horas, \(d, h)
        sprintf("%s01_%s_%s.wav", loc, d, h)))
      arquivos <- sort(arquivos)
      file.create(file.path(dir_audio, arquivos))

      linhas <- list()
      t0 <- 0
      for (arq in arquivos) {
        # ~15% das gravacoes sem nenhuma predicao
        if (stats::runif(1) < 0.15) { t0 <- t0 + 180; next }
        for (sp in sim_especies) {
          n <- stats::rpois(1, 2)
          if (n == 0) next
          offs <- sort(sample(seq(0, 177, by = 3), n))
          linhas[[length(linhas) + 1]] <- data.frame(
            begin = t0 + offs, offset = offs, sp = sp,
            conf = round(stats::runif(n, 0.05, 1), 4),
            path = paste0(sim_prefixo, "audio\\", loc, "\\", arq))
        }
        t0 <- t0 + 180
      }
      d <- do.call(rbind, linhas)
      tab <- data.frame(
        "Selection" = seq_len(nrow(d)), "View" = "Spectrogram 1",
        "Channel" = 1, "Begin Time (s)" = d$begin,
        "End Time (s)" = d$begin + 3, "Low Freq (Hz)" = 0,
        "High Freq (Hz)" = 15000, "Species Code" = d$sp,
        "Common Name" = sub("_.*$", "", d$sp), "Confidence" = d$conf,
        "Begin Path" = d$path, "File Offset (s)" = d$offset,
        check.names = FALSE)
      dir_tab <- file.path(raiz, "tabelas", locais[[loc]])
      dir.create(dir_tab, recursive = TRUE, showWarnings = FALSE)
      utils::write.table(tab, file.path(dir_tab, "BirdNET_SelectionTable.txt"),
                         sep = "\t", quote = FALSE, row.names = FALSE)
      out[[loc]] <- cbind(local = loc, tab)
    }
    invisible(do.call(rbind, out))
  })
}

# Lista de todas as gravacoes no formato da tabela_gravacoes da v1.2.0
# (colunas local e caminho_audio, caminhos estilo Windows)
simulate_recordings_table <- function(raiz) {
  do.call(rbind, lapply(c("ARA", "XAR", "BAI"), function(loc) {
    f <- list.files(file.path(raiz, "audio", loc))
    data.frame(local = loc,
               caminho_audio = paste0(sim_prefixo, "audio\\", loc, "\\", f))
  }))
}

# Simula a revisao no BirdNET GUI: cria arquivos vazios dos clipes em
# <dir_revisado>/<pasta>/{Positive,Negative}/ ou na pasta da especie (nao
# validados); alguns clipes nao sao criados (ausentes). P(positivo) =
# confidence (0.5 se NA).
simulate_review <- function(arquivo_clipe, pasta_especie, confidence,
                            dir_revisado, semente = 2) {
  withr::with_seed(semente, {
    u <- stats::runif(length(arquivo_clipe))
    destino <- ifelse(u < 0.05, NA,
               ifelse(u < 0.15, "",
               ifelse(stats::runif(length(u)) <
                        ifelse(is.na(confidence), 0.5, confidence),
                      "Positive", "Negative")))
    ok <- !is.na(destino)
    pastas <- file.path(dir_revisado, pasta_especie[ok], destino[ok])
    for (p in unique(pastas)) dir.create(p, recursive = TRUE,
                                         showWarnings = FALSE)
    file.create(file.path(pastas, arquivo_clipe[ok]))
    invisible(destino)
  })
}

# Validacoes no formato da v1.2.0 (validacao_por_clipe.csv): um data frame
# por local, com TP ~ Bernoulli(plogis(a_esp + b_esp * logit(conf) + u_loc))
simulate_validation <- function(locais = c("ARA", "XAR2", "BAI"), n = 80,
                                semente = 3) {
  withr::with_seed(semente, {
    esp <- sub("^.*_", "", sim_especies)
    a <- stats::setNames(c(-0.5, 0.5, -1.5), esp)
    b <- stats::setNames(c(1.2, 0.8, 1.5), esp)
    u <- stats::setNames(stats::rnorm(length(locais), 0, 0.5), locais)
    out <- list()
    for (loc in locais) {
      d <- do.call(rbind, lapply(seq_along(esp), function(i) {
        conf <- round(stats::runif(n, 0.1, 1), 4)
        p <- stats::plogis(a[[i]] + b[[i]] * stats::qlogis(conf) + u[[loc]])
        ver <- ifelse(stats::runif(n) < p, "positivo", "negativo")
        ver[sample(n, 3)] <- "nao_validado"
        data.frame(local = loc, species_code = sim_especies[i],
                   pasta_especie = gsub("-", "_", esp[i]),
                   confidence = conf, veredito = ver)
      }))
      out[[loc]] <- d
    }
    out
  })
}

# Historico de deteccao por noite no formato da v1.2.0, para as matrizes
simulate_history <- function(semente = 4) {
  withr::with_seed(semente, {
    noites <- format(c(as.Date("2022-01-03") + 0:20,
                       as.Date("2022-02-10") + 0:3,
                       as.Date("2022-03-01") + 0:9), "%Y%m%d")
    esp <- c("boa_ran", "den_nan", "sci_nas", "pse_par")
    h <- expand.grid(local = c("ARA", "XAR", "BAI"), especie = esp,
                     noite = noites, stringsAsFactors = FALSE)
    # nem toda especie aparece toda noite
    h <- h[stats::runif(nrow(h)) < 0.7, ]
    # XAR so grava a partir de fevereiro
    h <- h[!(h$local == "XAR" & h$noite < "20220201"), ]
    h$n_deteccoes  <- stats::rpois(nrow(h), 5) + 1L
    h$n_confiaveis <- stats::rbinom(nrow(h), h$n_deteccoes, 0.3)
    h$p_tp_max     <- round(stats::runif(nrow(h), 0.5, 1), 4)
    h$deteccao_k1  <- as.integer(h$n_confiaveis >= 1)
    h$deteccao_k2  <- as.integer(h$n_confiaveis >= 2)
    h$deteccao_k3  <- as.integer(h$n_confiaveis >= 3)
    h$deteccao     <- h$deteccao_k1
    h[order(h$local, h$especie, h$noite), ]
  })
}
