# =============================================================================
# diagrama_fluxo_validacao.R
#
# Fluxograma (DiagrammeR) do script extrair_clipes_validacao.R:
# da BirdNET_SelectionTable.txt de cada Local ate os pacotes de clipes
# prontos para validacao manual no BirdNET GUI.
#
# Uso: rode o script inteiro; o diagrama abre no Viewer do RStudio.
# Para exportar em PNG/SVG, veja o bloco final.
#
# Dependencias: install.packages("DiagrammeR")
#   (para exportar: install.packages(c("DiagrammeRsvg", "rsvg")))
# =============================================================================

library(DiagrammeR)

fluxo <- grViz('
digraph fluxo_validacao {

  graph [rankdir = TB, fontname = "Helvetica", fontsize = 13,
         nodesep = 0.45, ranksep = 0.55, bgcolor = "white",
         label = "extrair_clipes_validacao.R \u2014 do BirdNET aos pacotes de validacao",
         labelloc = "t", fontcolor = "#2c3e50"]

  node [fontname = "Helvetica", fontsize = 12, style = "filled,rounded",
        shape = box, penwidth = 1.1, color = "#8aa5b8",
        margin = "0.22,0.12"]
  edge [fontname = "Helvetica", fontsize = 10.5, color = "#7f8c99",
        fontcolor = "#5d6b78", arrowsize = 0.8]

  /* ---------------- ENTRADA (NAS) ---------------- */
  subgraph cluster_entrada {
    label = "\U0001F5C4  Entrada \u2014 NAS (N:/...)"
    fontcolor = "#1f5c8b"; color = "#bcd4e6"; style = "rounded"
    bgcolor = "#eef5fb"

    tabelas [label = "\U0001F4C4  BirdNET_SelectionTable.txt\numa por Local (pasta = nome do Local),\nconcatena as predicoes de cada audio",
             shape = note, fillcolor = "#ffffff"]
    audios  [label = "\U0001F3A7  Gravacoes .flac\n..._AAAAMMDD_HHMMSS.flac\n(coluna Begin Path)",
             shape = note, fillcolor = "#ffffff"]
  }

  /* ---------------- SELECAO ---------------- */
  subgraph cluster_selecao {
    label = "\U0001F50E  Selecao das predicoes"
    fontcolor = "#8a5a00"; color = "#ecd9b0"; style = "rounded"
    bgcolor = "#fdf6e9"

    ler      [label = "\U0001F4D6  1. Ler e padronizar as tabelas\n(readr) \u2014 Local = nome da pasta",
              fillcolor = "#fceecf"]
    remap    [label = "\U0001F9ED  2. Remapear caminhos (opcional)\nN:\\\\ \u2192 ponto de montagem\n(remap_de / remap_para)",
              fillcolor = "#fceecf"]
    datahora [label = "\U0001F4C5  3. Extrair data + hora\ndo nome da gravacao",
              fillcolor = "#fceecf"]
    filtro   [label = "\U0001F39A  4. Filtro opcional\nconfidence \u2265 conf_minima",
              fillcolor = "#fceecf"]
    top2     [label = "\U0001F3C6  5. Top-2 confidence por\nLocal \u00D7 Especie \u00D7 Data+Hora\n(dplyr)",
              fillcolor = "#f9e3ae"]
  }

  simular [label = "\u2753  simular = TRUE?", shape = diamond,
           style = "filled", fillcolor = "#f3e8fa", color = "#b393c9",
           margin = "0.12,0.08"]

  /* ---------------- CORTE ---------------- */
  subgraph cluster_corte {
    label = "\u2702  Corte e organizacao dos clipes"
    fontcolor = "#7a2e2e"; color = "#e6c3c3"; style = "rounded"
    bgcolor = "#fdf0f0"

    cortar [label = "\u2702  6. Cortar clipe .wav (pacote av / ffmpeg)\ninicio = File Offset (s)\nduracao = End Time \u2212 Begin Time\n(pula clipes ja existentes)",
            fillcolor = "#f9dcdc"]
    nomear [label = "\U0001F3F7  7. Nomear o clipe\n<conf>_<rank>_<arquivo original>_<ini>s_<fim>s.wav\ne.g. 0.104_1_DIVSPTS01_..._193000_0.0s_3.0s.wav",
            fillcolor = "#f9dcdc"]
    pastas [label = "\U0001F438  8. Uma pasta por especie\nclipes/boa_ran, clipes/lep_lab, ...",
            fillcolor = "#f9dcdc"]
  }

  /* ---------------- SAIDA ---------------- */
  subgraph cluster_saida {
    label = "\U0001F4E6  Saida"
    fontcolor = "#1e6b3a"; color = "#bcdcc6"; style = "rounded"
    bgcolor = "#eefaf1"

    manifesto [label = "\U0001F4CB  manifesto_clipes.csv\nlocal, especie, data, hora, rank,\nconfidence, audio de origem e status\n(ok \u00B7 ja_existia \u00B7 audio_nao_encontrado \u00B7 erro)",
               shape = note, fillcolor = "#ffffff"]
    zips      [label = "\U0001F4E6  9. Um zip por especie\npacotes/<especie>.zip\n(pacotes leves p/ download)",
               fillcolor = "#d9f2e0"]
  }

  gui [label = "\u2705  Validacao manual no BirdNET GUI (review)\n\u2192 clipes validados alimentam o retreino (V1 \u2192 V2)",
       fillcolor = "#dff0d8", color = "#7cae7c", penwidth = 1.4]

  /* ---------------- FLUXO ---------------- */
  tabelas  -> ler
  ler      -> remap
  remap    -> datahora
  datahora -> filtro
  filtro   -> top2
  top2     -> simular
  simular  -> cortar    [label = " nao \u2014 cortar de verdade"]
  simular  -> manifesto [label = " sim \u2014 so gera o manifesto\n (ensaio, sem cortar audio)", style = dashed]
  audios   -> cortar    [label = " audio de origem\n (Begin Path)", style = dashed]
  cortar   -> nomear
  nomear   -> pastas
  pastas   -> manifesto
  pastas   -> zips
  zips     -> gui
  manifesto -> gui [style = dashed, label = " conferencia"]
}
')

fluxo  # abre no Viewer

# -----------------------------------------------------------------------------
# Exportar como PNG e SVG (opcional)
# -----------------------------------------------------------------------------
if (requireNamespace("DiagrammeRsvg", quietly = TRUE) &&
    requireNamespace("rsvg", quietly = TRUE)) {
  svg_txt <- DiagrammeRsvg::export_svg(fluxo)
  rsvg::rsvg_png(charToRaw(svg_txt), "fluxo_extracao_clipes.png", width = 2400)
  rsvg::rsvg_svg(charToRaw(svg_txt), "fluxo_extracao_clipes.svg")
  message("Diagrama exportado: fluxo_extracao_clipes.png / .svg")
} else {
  message("Para exportar PNG/SVG: install.packages(c('DiagrammeRsvg', 'rsvg'))")
}
