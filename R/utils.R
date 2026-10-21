# Funcoes auxiliares internas

# Converte caminhos do estilo Windows (N:\Arara\...) para barras normais,
# aplicando o remapeamento opcional de prefixo
remap_path <- function(caminho, de = NULL, para = NULL) {
  caminho <- str_replace_all(caminho, fixed("\\"), "/")
  if (!is.null(de) && !is.null(para)) {
    de <- str_replace_all(de, fixed("\\"), "/")
    caminho <- str_replace(caminho, fixed(de), para)
  }
  caminho
}

# Extrai data (AAAAMMDD) e hora (HH) do nome do arquivo de gravacao,
# assumindo o padrao <...>_AAAAMMDD_HHMMSS.<ext> dos gravadores
parse_date_hour <- function(nome_arquivo) {
  m <- str_match(nome_arquivo, "(\\d{8})_(\\d{6})")
  tibble(
    recording_date = m[, 2],
    recording_hour = str_sub(m[, 3], 1, 2)
  )
}

# Codigo curto da especie para nome de pasta: parte final do rotulo do
# classificador, ex. "Adenomera diptyx_ade-dip" -> "ade_dip"; se o rotulo
# ja for curto ("ade-dip"), funciona igual
folder_name <- function(species_code) {
  str_replace_all(str_extract(species_code, "[^_]+$"), "-", "_")
}

# Exige um pacote de Suggests
require_suggested <- function(pkg, para) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop("Package '", pkg, "' is needed ", para, ". Install it with ",
         "install.packages(\"", pkg, "\").", call. = FALSE)
  }
}
