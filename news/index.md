# Changelog

## sheepdog (development version)

- New articles, run on a simulated example data set:
  [`vignette("sheepdog")`](https://provetelab.org/sheepdog/articles/sheepdog.md)
  (Get started),
  [`vignette("sampling-designs")`](https://provetelab.org/sheepdog/articles/sampling-designs.md),
  [`vignette("validation-effort")`](https://provetelab.org/sheepdog/articles/validation-effort.md),
  [`vignette("calibration")`](https://provetelab.org/sheepdog/articles/calibration.md),
  [`vignette("community-matrices")`](https://provetelab.org/sheepdog/articles/community-matrices.md)
  and
  [`vignette("retraining")`](https://provetelab.org/sheepdog/articles/retraining.md)
  (training folders for BirdNET-Analyzer from the reviewed clips).
- The example data set (4 sites x 8 species x 6 months; selection
  tables, the list of recordings, reviewed clips and a calibrated
  nightly history) ships in
  `system.file("extdata", "example", package = "sheepdog")`;
  `data-raw/make_example_data.R` generates it.
- [`plot_precision()`](https://provetelab.org/sheepdog/reference/plot_precision.md)
  draws one line per site when the table has several sites; before, the
  lines of different sites were joined in the same panel (also in the
  `precision_by_bin.png` of
  [`post_validation()`](https://provetelab.org/sheepdog/reference/post_validation.md)).
- [`vignette("community-matrices")`](https://provetelab.org/sheepdog/articles/community-matrices.md)
  uses a PCoA on square-root Bray-Curtis
  ([`ape::pcoa()`](https://rdrr.io/pkg/ape/man/pcoa.html)) and a
  binomial GLLVM (‘gllvm’) for a model-based ordination and a test of
  the season effect; ‘ape’, ‘gllvm’ and ‘vegan’ are suggested packages,
  used only there.
- The vignette `crywolf-contract` is now `crywolf-integration`
  (“Integration with crywolf”).

## sheepdog 2.0.0

The four scripts of birdnet-validation-sampler v1.2.0 become the R
package **sheepdog**. With the same settings and seed, the package
writes the same tables as v1.2.0, after the renaming below; the test
suite checks this against outputs of the v1.2.0 scripts on simulated
data. The scripts are preserved in the `v1.2.0` tag.

### From scripts to functions

| v1.2.0 script | sheepdog |
|----|----|
| `extrair_clipes_validacao.R` | [`extract_validation_clips()`](https://provetelab.org/sheepdog/reference/extract_validation_clips.md); steps [`read_selection_tables()`](https://provetelab.org/sheepdog/reference/read_selection_tables.md), [`select_clips()`](https://provetelab.org/sheepdog/reference/select_clips.md), [`cut_clips()`](https://provetelab.org/sheepdog/reference/cut_clips.md), [`pack_clips()`](https://provetelab.org/sheepdog/reference/pack_clips.md) |
| `pos_validacao.R` | [`post_validation()`](https://provetelab.org/sheepdog/reference/post_validation.md); steps [`classify_review()`](https://provetelab.org/sheepdog/reference/classify_review.md), [`precision_by_bin()`](https://provetelab.org/sheepdog/reference/precision_by_bin.md), [`suggest_thresholds()`](https://provetelab.org/sheepdog/reference/suggest_thresholds.md), [`nightly_presence()`](https://provetelab.org/sheepdog/reference/nightly_presence.md), [`retraining_clips()`](https://provetelab.org/sheepdog/reference/retraining_clips.md), [`plot_precision()`](https://provetelab.org/sheepdog/reference/plot_precision.md) |
| `calibracao.R` | [`calibrate()`](https://provetelab.org/sheepdog/reference/calibrate.md); steps [`read_validations()`](https://provetelab.org/sheepdog/reference/read_validations.md), [`calibration_models()`](https://provetelab.org/sheepdog/reference/calibration_models.md), [`compare_calibration_models()`](https://provetelab.org/sheepdog/reference/compare_calibration_models.md), [`fit_calibration()`](https://provetelab.org/sheepdog/reference/fit_calibration.md), [`calibration_effort()`](https://provetelab.org/sheepdog/reference/calibration_effort.md), [`score_detections()`](https://provetelab.org/sheepdog/reference/score_detections.md), [`detection_history()`](https://provetelab.org/sheepdog/reference/detection_history.md), [`summarise_history()`](https://provetelab.org/sheepdog/reference/summarise_history.md), [`plot_calibration()`](https://provetelab.org/sheepdog/reference/plot_calibration.md) |
| `gerar_matrizes_comunidade.R` | [`build_community_matrices()`](https://provetelab.org/sheepdog/reference/build_community_matrices.md); step [`community_matrices()`](https://provetelab.org/sheepdog/reference/community_matrices.md) |

[`select_clips()`](https://provetelab.org/sheepdog/reference/select_clips.md)
is a pure function: it returns the clip manifest without reading or
writing audio.

### Settings become arguments

Defaults are those of the `config` blocks, except project paths and
project-specific lists, which are now required arguments (or `NULL`).

| v1.2.0 `config` | argument |
|----|----|
| `dir_dados`, `padrao_tabela` | `data_dir`, `table_pattern` |
| `dir_saida` | `output_dir` |
| `modo_amostragem` | `sampling_mode` |
| `unidade_ocasiao` (`"arquivo"`, `"minuto"`) | `occasion_unit` (`"file"`, `"minute"`) |
| `limiar` | `threshold` |
| `n_top` | `n_top` |
| `fracao_gravacoes`, `n_gravacoes_por_local` | `recording_fraction`, `n_recordings_per_site` |
| `tabela_gravacoes`, `padrao_audio`, `duracao_gravacao` | `recordings`, `audio_pattern`, `recording_duration` |
| `conf_minima` | `min_confidence` |
| `locais`, `especies` | `sites`, `species` |
| `data_inicio`, `data_fim` | `date_start`, `date_end` |
| `hora_inicio`, `hora_fim` | `hour_start`, `hour_end` |
| `alternar_dias` | `alternate_days` |
| `meta_total`, `max_por_especie` | `target_total`, `max_per_species` |
| `balancear_por_hora` | `balance_by_hour` |
| `remap_de`, `remap_para` | `remap_from`, `remap_to` |
| `fazer_zip`, `simular` | `make_zip`, `simulate` |
| seed 2026 (fixed) | `seed = 2026` |
| `dir_validado`, `caminho_manifesto` | `review_dir`, `manifest_path` |
| `padrao_positivo`, `padrao_negativo` | `positive_pattern`, `negative_pattern` |
| `faixas`, `precisao_alvo`, `n_minimo` | `bins`, `target_precision`, `min_n` |
| `arquivos_validacao`, `tabelas_predicao` | `validation_files`, `prediction_tables` |
| `normalizar_locais` | `site_map` (default `NULL`) |
| `p_min`, `min_deteccoes_noite`, `hora_madrugada` | `p_min`, `min_detections_night`, `dawn_hour` |
| `k_folds`, `semente` | `k_folds`, `seed` |
| `fazer_curva_esforco`, `esforco_n`, `esforco_repeticoes` | `effort_curve`, `effort_n`, `effort_reps` |
| `arquivo_historico` | `history_file` |
| `k_min`, `especies_nucleo`, `min_noites_mes` | `k_min`, `core_species` (required), `min_nights_month` |

### Output files, columns and values in English

- Files: `manifesto_clipes.csv` → `clip_manifest.csv`;
  `validacao_por_clipe.csv` → `validation_by_clip.csv`;
  `precisao_por_faixa` → `precision_by_bin`; `thresholds_sugeridos` →
  `suggested_thresholds`; `presenca_por_noite` → `nightly_presence`;
  `clipes_para_retreino` → `retraining_clips`; `comparacao_modelos` →
  `model_comparison`; `modelo_calibracao` → `calibration_model`;
  `curvas_calibradas` → `calibration_curves`; `curva_esforco` →
  `effort_curve`; `deteccoes_calibradas_<local>` →
  `calibrated_detections_<site>`; `historico_deteccao_noite` →
  `nightly_detection_history`; `resumo_deteccao_especie_local` →
  `detection_summary`; `matriz_frequencia_local_mes_k<k>` →
  `frequency_matrix_site_month_k<k>`; `matriz_contagens_local_mes_k<k>`
  → `count_matrix_site_month_k<k>`; `esforco_local_mes` →
  `effort_site_month`. Folders `clipes/` and `pacotes/` → `clips/` and
  `packages/`.
- Columns and values of the manifest and the validation table: see
  `vignette("crywolf-contract")`. Other columns: `especie` → `species`,
  `data` → `date`, `hora` → `hour`, `n_deteccoes` → `n_detections`,
  `n_confiaveis` → `n_reliable`, `deteccao(_k1..k3)` →
  `detection(_k1..k3)`, `faixa` → `bin`, `n_validados` → `n_reviewed`,
  `n_positivos` → `n_positive`, `precisao` → `precision`,
  `pouco_suporte` → `low_support`, `n_suporte` → `n_support`,
  `precisao_no_corte` → `precision_at_threshold`, `n_clipes` →
  `n_clips`, `presenca` → `presence` (`confirmed`,
  `not_detected_in_reviewed`, `not_reviewed`), `conf_max_positivo` →
  `max_confidence_positive`, `modelo` → `model`, `auc_media`/`auc_dp` →
  `auc_mean`/`auc_sd`, `n_por_celula` → `n_per_cell`, `noites(_k1..k3)`
  → `nights(_k1..k3)`, `mes` → `month`, `n_noites_gravadas` →
  `n_nights_recorded`, `incluido` → `included`, `n_noites_deteccao` →
  `n_nights_detected`, `frequencia` → `frequency`.
- Calibration models: `m1_int_especie` → `m1_species_intercept`,
  `m2_slope_especie` → `m2_species_slope`, `m3_mais_local` →
  `m3_plus_site`, `m4_especie_x_local` → `m4_species_x_site`; the model
  terms use `species` and `site`.
- Whole-recording clips are named `rec_...` instead of `grav_...`.
- Messages, warnings and errors are in English.

### Reading v1.2.0 files

[`post_validation()`](https://provetelab.org/sheepdog/reference/post_validation.md),
[`classify_review()`](https://provetelab.org/sheepdog/reference/classify_review.md),
[`calibrate()`](https://provetelab.org/sheepdog/reference/calibrate.md),
[`read_validations()`](https://provetelab.org/sheepdog/reference/read_validations.md),
[`community_matrices()`](https://provetelab.org/sheepdog/reference/community_matrices.md)
and
[`build_community_matrices()`](https://provetelab.org/sheepdog/reference/build_community_matrices.md)
read manifests, validation tables and histories written by v1.2.0 and
rename them on reading, so validated data stay usable.

### Changes in behaviour

- Random draws use
  [`withr::with_seed()`](https://withr.r-lib.org/reference/with_seed.html):
  the draws are those of v1.2.0, and the global random number generator
  is left as it was.
- [`suggest_thresholds()`](https://provetelab.org/sheepdog/reference/suggest_thresholds.md)
  returns an empty table when no reviewed clip has a confidence score
  (whole recordings only); v1.2.0 wrote a row of `NA`.
- The verdict patterns of the review are case-insensitive and only match
  the subfolders below `review_dir`, not the review folder itself.
- A manifest without a `confidence` column is accepted.
- [`score_detections()`](https://provetelab.org/sheepdog/reference/score_detections.md)
  warns about prediction tables named after a site that is not in the
  calibration, and keeps the site name in the output.
- The random-effects models of the calibration need ‘lme4’, and the
  package now stops when it is missing instead of letting those fits
  fail.
- ‘av’, ‘lme4’ and ‘ggplot2’ are suggested packages, needed only to cut
  audio, to fit hierarchical models and to draw the figures.
