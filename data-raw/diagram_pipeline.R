# =============================================================================
# diagram_pipeline.R
#
# Esquema (DiagrammeR) dos tres estagios do sheepdog, com as funcoes e os
# arquivos de cada um:
#   1. Dados de validacao (extracao -> revisao manual -> TP/FP)
#   2. Calibracao (score -> probabilidade)
#   3. Matrizes de comunidade
#
# Uso: rode o script inteiro a partir da raiz do repositorio; o diagrama
# abre no Viewer do RStudio e e exportado para man/figures/pipeline.png.
# Dependencias: install.packages(c("DiagrammeR", "DiagrammeRsvg", "rsvg"))
# =============================================================================

library(DiagrammeR)

fluxo <- grViz('
digraph pipeline {

  graph [rankdir = TB, fontname = "Helvetica", fontsize = 13,
         nodesep = 0.4, ranksep = 0.5, bgcolor = "white",
         label = "sheepdog: from BirdNET detections to analysis-ready data",
         labelloc = "t", fontcolor = "#2c3e50"]

  node [fontname = "Helvetica", fontsize = 11.5, style = "filled,rounded",
        shape = box, penwidth = 1.1, color = "#8aa5b8", margin = "0.2,0.11"]
  edge [fontname = "Helvetica", fontsize = 10, color = "#7f8c99",
        fontcolor = "#5d6b78", arrowsize = 0.8]

  audios [label = "Recordings\n..._YYYYMMDD_HHMMSS (.wav, .flac, .mp3)",
          shape = note, fillcolor = "#ffffff", color = "#b8b8b8"]
  birdnet [label = "BirdNET custom classifier\nBirdNET_SelectionTable.txt per site",
           fillcolor = "#eeeeee", color = "#9a9a9a"]

  /* ------- ESTAGIO 1: dados de validacao ------- */
  subgraph cluster_e1 {
    label = "Stage 1. Validation data"
    fontcolor = "#1f5c8b"; color = "#bcd4e6"; style = "rounded"
    bgcolor = "#eef5fb"

    extrair [label = "extract_validation_clips()\nread_selection_tables() > select_clips()\n> cut_clips() > pack_clips()",
             fillcolor = "#d9e9f8"]
    manifesto [label = "clip_manifest.csv\nclips/<species_folder>/, packages/<species_folder>.zip",
               shape = note, fillcolor = "#ffffff"]
    gui [label = "Manual review in the BirdNET GUI\nPositive / Negative folders",
         fillcolor = "#d9e9f8"]
    posval [label = "post_validation()\nclassify_review(), precision_by_bin(),\nsuggest_thresholds(), nightly_presence()",
            fillcolor = "#d9e9f8"]
    tpfp [label = "validation_by_clip.csv\nmanifest + verdict per clip\n(positive / negative / not reviewed)",
          shape = note, fillcolor = "#ffffff"]
  }

  /* ------- ESTAGIO 2: calibracao ------- */
  subgraph cluster_e2 {
    label = "Stage 2. Calibration: score to probability"
    fontcolor = "#8a5a00"; color = "#ecd9b0"; style = "rounded"
    bgcolor = "#fdf6e9"

    cv [label = "compare_calibration_models()\nfive models, from tp ~ logit(conf) to\n+ (logit(conf) | species) + (1 | site:species);\nk-fold AUC",
        fillcolor = "#fceecf"]
    fit [label = "fit_calibration()\nbest model refitted to all clips",
         fillcolor = "#fceecf"]
    prever [label = "score_detections()\nP(TP) for every detection\n(calibrated species only)",
            fillcolor = "#f9e3ae"]
    historico [label = "detection_history()\nnightly_detection_history.csv\nP(TP) >= p_min, repetition rule k = 1, 2, 3",
               fillcolor = "#f9e3ae"]
  }

  /* ------- ESTAGIO 3: matrizes ------- */
  subgraph cluster_e3 {
    label = "Stage 3. Community matrices"
    fontcolor = "#1e6b3a"; color = "#bcdcc6"; style = "rounded"
    bgcolor = "#eefaf1"

    matrizes [label = "build_community_matrices()\nsite x month, core species, k >= k_min\nnights with detection / nights recorded",
              fillcolor = "#d9f2e0"]
  }

  ordenacoes [label = "Multivariate ordinations\n(PCoA, NMDS, RDA)",
              fillcolor = "#f3e8fa", color = "#b393c9"]

  occupancy [label = "Occupancy models with false positives\n(e.g. crywolf)",
             fillcolor = "#f3e8fa", color = "#b393c9"]
  retreino [label = "retraining_clips.csv\nclassifier retraining",
            fillcolor = "#f3e8fa", color = "#b393c9"]

  /* ------- FLUXO ------- */
  audios  -> birdnet
  birdnet -> extrair
  extrair -> manifesto
  manifesto -> gui
  gui     -> posval
  posval  -> tpfp
  tpfp    -> cv [label = " calibrate()"]
  cv      -> fit [label = " best model"]
  fit     -> prever
  birdnet -> prever [label = " every detection\n (not only the reviewed ones)", style = dashed]
  prever  -> historico
  historico -> matrizes
  matrizes -> ordenacoes
  tpfp    -> occupancy [label = " random designs\n (see crywolf contract)", style = dashed]
  posval  -> retreino [style = dashed]
}
')

fluxo  # abre no Viewer

svg_txt <- DiagrammeRsvg::export_svg(fluxo)
rsvg::rsvg_png(charToRaw(svg_txt), "man/figures/pipeline.png", width = 2400)
message("Diagram written to man/figures/pipeline.png")
