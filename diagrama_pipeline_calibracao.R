# =============================================================================
# diagrama_pipeline_calibracao.R
#
# Esquema (DiagrammeR) da arquitetura em tres estagios do pipeline FrogNet:
#   1. Fabrica de dados de calibracao (extracao -> validacao manual -> TP/FP)
#   2. Calibracao (GLMM hierarquico score -> probabilidade)
#   3. Produtos (historicos de deteccao, matrizes de comunidade,
#      diagnostico, retreino V2)
#
# Uso: rode o script inteiro; o diagrama abre no Viewer do RStudio.
# Dependencias: install.packages("DiagrammeR")
#   (exportar: install.packages(c("DiagrammeRsvg", "rsvg")))
# =============================================================================

library(DiagrammeR)

fluxo <- grViz('
digraph pipeline_calibracao {

  graph [rankdir = TB, fontname = "Helvetica", fontsize = 13,
         nodesep = 0.4, ranksep = 0.5, bgcolor = "white",
         label = "Pipeline FrogNet — da gravação à análise de comunidades, com calibração do BirdNET",
         labelloc = "t", fontcolor = "#2c3e50"]

  node [fontname = "Helvetica", fontsize = 11.5, style = "filled,rounded",
        shape = box, penwidth = 1.1, color = "#8aa5b8", margin = "0.2,0.11"]
  edge [fontname = "Helvetica", fontsize = 10, color = "#7f8c99",
        fontcolor = "#5d6b78", arrowsize = 0.8]

  audios [label = "\U0001F3A7  Gravações .flac no NAS\n7 locais · 2021–2025",
          shape = note, fillcolor = "#ffffff", color = "#b8b8b8"]
  birdnet [label = "\U0001F916  BirdNET (classificador local V1)\nBirdNET_SelectionTable.txt por local",
           fillcolor = "#eeeeee", color = "#9a9a9a"]

  /* ------- ESTAGIO 1: fabrica de dados de calibracao ------- */
  subgraph cluster_e1 {
    label = "\U0001F3ED  Estágio 1 — Fábrica de dados de calibração"
    fontcolor = "#1f5c8b"; color = "#bcd4e6"; style = "rounded"
    bgcolor = "#eef5fb"

    extrair [label = "✂  extrair_clipes_validacao.R\namostra balanceada por espécie × hora\n(16h–6h, noites alternadas, 1.500/local, seed fixa)",
             fillcolor = "#d9e9f8"]
    gui [label = "\U0001F464  Validação manual — BirdNET GUI (Massao)\nPositive / Negative por clipe",
         fillcolor = "#d9e9f8"]
    posval [label = "\U0001F4CB  pos_validacao.R\ncruza revisão × manifesto",
            fillcolor = "#d9e9f8"]
    tpfp [label = "✅❌  validacao_por_clipe.csv\n6.304 clipes rotulados TP/FP\n16 espécies × 7 locais",
          shape = note, fillcolor = "#ffffff"]
  }

  /* ------- ESTAGIO 2: calibracao ------- */
  subgraph cluster_e2 {
    label = "\U0001F4D0  Estágio 2 — calibracao.R: score → probabilidade"
    fontcolor = "#8a5a00"; color = "#ecd9b0"; style = "rounded"
    bgcolor = "#fdf6e9"

    glmm [label = "\U0001F4C8  GLMM binomial\nTP ~ logit(conf) + (logit(conf) | espécie)\n+ (1 | local:espécie)",
          fillcolor = "#fceecf"]
    cv [label = "\U0001F500  Validação cruzada (5-fold)\nAUC 0,93 (espécie × local)\nvs 0,82 (score puro)",
        fillcolor = "#fceecf"]
    prever [label = "\U0001F52E  P(TP) prevista para a BASE COMPLETA\n(~1 milhão de detecções/local;\nsó espécies calibradas)",
            fillcolor = "#f9e3ae"]
  }

  /* ------- ESTAGIO 3: produtos ------- */
  subgraph cluster_e3 {
    label = "\U0001F381  Estágio 3 — Produtos"
    fontcolor = "#1e6b3a"; color = "#bcdcc6"; style = "rounded"
    bgcolor = "#eefaf1"

    historico [label = "\U0001F4C5  historico_deteccao_noite.csv\nP(TP) ≥ 0,95 + regra de repetição\n(k = 1/2/3 como sensibilidade)",
               fillcolor = "#d9f2e0"]
    matrizes [label = "\U0001F9EE  gerar_matrizes_comunidade.R\nmatriz local × mês (k ≥ 2, espécies-núcleo)\nfreq. de noites padronizada pelo esforço",
              fillcolor = "#d9f2e0"]
    ordenacoes [label = "\U0001F438  Ordenações multivariadas (Daiene)\nsem camada p/ FP → filtro rígido na entrada",
              fillcolor = "#d9f2e0"]
    curvas [label = "\U0001F4CA  Curvas calibradas por\nespécie × local (diagnóstico)",
            fillcolor = "#d9f2e0"]
    retreino [label = "\U0001F504  clipes_para_retreino.csv\npositivos + hard negatives\n(boa-pun, tra-typ, ade-dip, lep-ele)",
              fillcolor = "#d9f2e0"]
  }

  v2 [label = "\U0001F9E0  Retreino → classificador V2\n(foco nas espécies fracas)",
      fillcolor = "#f3e8fa", color = "#b393c9"]

  /* ------- FLUXO ------- */
  audios  -> birdnet
  birdnet -> extrair
  extrair -> gui
  gui     -> posval
  posval  -> tpfp
  tpfp    -> glmm
  glmm    -> cv
  cv      -> prever [label = " melhor modelo"]
  birdnet -> prever [label = " todas as predições\n (não só as validadas)", style = dashed]
  prever  -> historico
  historico -> matrizes
  matrizes -> ordenacoes
  prever  -> curvas
  posval  -> retreino [style = dashed]
  curvas  -> retreino [label = " quem precisa\n de retreino", style = dashed]
  retreino -> v2
  v2 -> birdnet [label = " novo ciclo:\n reanalisar + recalibrar", style = dashed,
                 constraint = false, color = "#b393c9", fontcolor = "#8a5a9b"]
}
')

fluxo  # abre no Viewer

if (requireNamespace("DiagrammeRsvg", quietly = TRUE) &&
    requireNamespace("rsvg", quietly = TRUE)) {
  svg_txt <- DiagrammeRsvg::export_svg(fluxo)
  rsvg::rsvg_png(charToRaw(svg_txt), "pipeline_calibracao.png", width = 2400)
  message("Diagrama exportado: pipeline_calibracao.png")
} else {
  message("Para exportar PNG: install.packages(c('DiagrammeRsvg', 'rsvg'))")
}
