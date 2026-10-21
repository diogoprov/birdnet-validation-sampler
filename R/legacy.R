# Leitura de arquivos no formato da v1.2.0 (colunas e valores em portugues).
# O mapa abaixo e o mesmo documentado no NEWS.md e na vignette do contrato.

legacy_columns <- c(
  # manifesto e validacao por clipe
  local               = "site",
  pasta_especie       = "species_folder",
  data_gravacao       = "recording_date",
  noite               = "night",
  hora_gravacao       = "recording_hour",
  arquivo_clipe       = "clip_file",
  inicio_clipe        = "clip_start",
  fim_clipe           = "clip_end",
  duracao             = "duration",
  audio_origem        = "source_audio",
  begin_path_original = "begin_path",
  modo_amostragem     = "sampling_mode",
  ocasiao_id          = "occasion_id",
  n_deteccoes_ocasiao = "n_detections_occasion",
  prob_inclusao       = "inclusion_prob",
  veredito            = "verdict",
  caminho_wav         = "reviewed_path",
  # tabela de gravacoes (tabela_gravacoes)
  caminho_audio       = "source_audio",
  # historico de deteccao por noite
  especie             = "species",
  n_deteccoes         = "n_detections",
  n_confiaveis        = "n_reliable",
  deteccao_k1         = "detection_k1",
  deteccao_k2         = "detection_k2",
  deteccao_k3         = "detection_k3",
  deteccao            = "detection"
)

legacy_values <- list(
  verdict = c(positivo = "positive", negativo = "negative",
              nao_validado = "not_reviewed", clipe_ausente = "clip_missing"),
  sampling_mode = c(top = "top", aleatorio_deteccoes = "random_detections",
                    aleatorio_gravacoes = "random_recordings"),
  status = c(ja_existia = "already_exists",
             audio_nao_encontrado = "audio_not_found",
             simulado = "simulated", ok = "ok")
)

# Arquivo no formato antigo? (tem 'local' e nao tem 'site')
is_legacy <- function(df) "local" %in% names(df) && !"site" %in% names(df)

# Renomeia colunas e recodifica valores do formato v1.2.0; tabelas ja no
# formato atual passam intactas. clip_file NAO muda (prefixo "grav_" dos
# clipes antigos): e o nome do arquivo no disco, usado para casar a revisao
from_legacy <- function(df) {
  if (!is_legacy(df)) return(df)
  velhas <- intersect(names(legacy_columns), names(df))
  df <- rename(df, !!!setNames(velhas, legacy_columns[velhas]))
  for (col in intersect(names(legacy_values), names(df))) {
    mapa <- legacy_values[[col]]
    x <- df[[col]]
    df[[col]] <- ifelse(x %in% names(mapa), unname(mapa[x]), x)
  }
  if ("status" %in% names(df)) {
    df$status <- str_replace(df$status, "^erro: ", "error: ")
  }
  df
}
