# sheepdog (development version)

## Calibration

- `compare_calibration_models()` also scores the predicted probabilities on
  the held-out folds: log-loss and Brier score (proper scoring rules),
  calibration intercept and slope, the share of singular fold fits
  (`prop_singular`) and the position of each model (`complexity`).
- New `select_calibration_model()`, with the rules `"best_auc"` (the rule
  of 2.x) and `"one_se_logloss"` (the simplest model within one standard
  error of the lowest log-loss, leaving out singular fits).
  `calibrate()` takes the rule in `select`; the default stays
  `"best_auc"` until 3.0.0, when it becomes `"one_se_logloss"`.
- `calibration_models(uncorrelated = TRUE)` adds
  `m5_species_x_site_uncorrelated`, the m4 structure without the
  correlation between the species intercepts and slopes, which avoids the
  singular fits of m4; `calibrate()` takes it with `uncorrelated = TRUE`.

## Sampling

- `select_clips()` gains `strata` (`"night_hour"`, the rule of 2.0.0,
  `"night"` or `"site_species"`) for the occasion draw of
  `"random_detections"`. With one recording per hour, the default stratum
  holds a single occasion and draws nothing; a coarser stratum makes the
  draw random. A coarser stratum combined with `balance_by_hour = TRUE`
  under a target or limit warns that `inclusion_prob` is conditional on
  the first draw.
- `extract_validation_clips()` writes `extraction_info.csv` with the
  provenance of the run (date, versions of sheepdog and R, folder of the
  tables, the new `classifier` label and every argument of
  `select_clips()`).
- The message on predictions dropped by `min_confidence` is no longer
  printed when none is dropped.

# sheepdog 2.1.0

## Bug fixes

- `classify_review()` classified the clips wrongly on Windows when
  `review_dir` had backslashes (e.g. `E:\validation\clips`): the name of
  the review folder entered the search for the verdict, so a folder named
  after a verdict marked every clip with it.

## Warnings and diagnostics

- `fit_calibration()` warns when the fitted GLMM is singular (a variance
  estimated at zero or a correlation at +-1); `calibrate()` passes the
  warning on.
- `compare_calibration_models()` warns about, and counts in the new column
  `n_failed`, the folds whose fit failed; before, they were silently left
  out of the mean AUC.
- `calibration_effort()` warns when `n_train` exceeds the smallest site x
  species cell minus five, and returns `n_train_mean`, `n_test_mean` and
  `n_failed`.
- The documentation of `select_clips()` explains that `target_total` gives
  rare species higher inclusion probabilities (weight pooled estimates by
  `1 / inclusion_prob`) and that the default `recording_fraction = 0.01`
  draws one recording per site in small projects.

## Documentation

- New articles, run on a simulated example data set:
  `vignette("sheepdog")` (Get started), `vignette("sampling-designs")`,
  `vignette("validation-effort")`, `vignette("calibration")`,
  `vignette("community-matrices")` and `vignette("retraining")`
  (training folders for BirdNET-Analyzer from the reviewed clips).
- The example data set (4 sites x 8 species x 6 months; selection tables,
  the list of recordings, reviewed clips and a calibrated nightly history)
  ships in `system.file("extdata", "example", package = "sheepdog")`;
  `data-raw/make_example_data.R` generates it.
- `plot_precision()` draws one line per site when the table has several
  sites; before, the lines of different sites were joined in the same panel
  (also in the `precision_by_bin.png` of `post_validation()`).
- `vignette("community-matrices")` uses a PCoA on square-root
  Bray-Curtis (`ape::pcoa()`) and a binomial GLLVM ('gllvm') for a
  model-based ordination and a test of the season effect; 'ape', 'gllvm'
  and 'vegan' are suggested packages, used only there.
- The vignette `crywolf-contract` is now `crywolf-integration`
  ("Integration with crywolf").
- The repository was renamed to `diogoprov/sheepdog`; the package site is
  <https://provetelab.org/sheepdog/>.
- The package can be installed from r-universe
  (`install.packages("sheepdog", repos = c("https://diogoprov.r-universe.dev",
  "https://cloud.r-project.org"))`), with binaries for Windows, macOS and
  Linux.

## Tests

- The comparisons with the v1.2.0 outputs tolerate floating-point
  differences between platforms (relative tolerance 1e-3 for the
  calibration outputs, 1e-8 for the others); R CMD check runs on macOS,
  Windows and Ubuntu in GitHub Actions.

# sheepdog 2.0.0

The four scripts of birdnet-validation-sampler v1.2.0 become the R package
**sheepdog**. With the same settings and seed, the package writes the same
tables as v1.2.0, after the renaming below; the test suite checks this
against outputs of the v1.2.0 scripts on simulated data. The scripts are
preserved in the `v1.2.0` tag.

## From scripts to functions

| v1.2.0 script | sheepdog |
|---|---|
| `extrair_clipes_validacao.R` | `extract_validation_clips()`; steps `read_selection_tables()`, `select_clips()`, `cut_clips()`, `pack_clips()` |
| `pos_validacao.R` | `post_validation()`; steps `classify_review()`, `precision_by_bin()`, `suggest_thresholds()`, `nightly_presence()`, `retraining_clips()`, `plot_precision()` |
| `calibracao.R` | `calibrate()`; steps `read_validations()`, `calibration_models()`, `compare_calibration_models()`, `fit_calibration()`, `calibration_effort()`, `score_detections()`, `detection_history()`, `summarise_history()`, `plot_calibration()` |
| `gerar_matrizes_comunidade.R` | `build_community_matrices()`; step `community_matrices()` |

`select_clips()` is a pure function: it returns the clip manifest without
reading or writing audio.

## Settings become arguments

Defaults are those of the `config` blocks, except project paths and
project-specific lists, which are now required arguments (or `NULL`).

| v1.2.0 `config` | argument |
|---|---|
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

## Output files, columns and values in English

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
  `frequency_matrix_site_month_k<k>`; `matriz_contagens_local_mes_k<k>` →
  `count_matrix_site_month_k<k>`; `esforco_local_mes` →
  `effort_site_month`. Folders `clipes/` and `pacotes/` → `clips/` and
  `packages/`.
- Columns and values of the manifest and the validation table: see
  `vignette("crywolf-contract")`. Other columns: `especie` → `species`,
  `data` → `date`, `hora` → `hour`, `n_deteccoes` → `n_detections`,
  `n_confiaveis` → `n_reliable`, `deteccao(_k1..k3)` → `detection(_k1..k3)`,
  `faixa` → `bin`, `n_validados` → `n_reviewed`, `n_positivos` →
  `n_positive`, `precisao` → `precision`, `pouco_suporte` → `low_support`,
  `n_suporte` → `n_support`, `precisao_no_corte` →
  `precision_at_threshold`, `n_clipes` → `n_clips`, `presenca` →
  `presence` (`confirmed`, `not_detected_in_reviewed`, `not_reviewed`),
  `conf_max_positivo` → `max_confidence_positive`, `modelo` → `model`,
  `auc_media`/`auc_dp` → `auc_mean`/`auc_sd`, `n_por_celula` →
  `n_per_cell`, `noites(_k1..k3)` → `nights(_k1..k3)`, `mes` → `month`,
  `n_noites_gravadas` → `n_nights_recorded`, `incluido` → `included`,
  `n_noites_deteccao` → `n_nights_detected`, `frequencia` → `frequency`.
- Calibration models: `m1_int_especie` → `m1_species_intercept`,
  `m2_slope_especie` → `m2_species_slope`, `m3_mais_local` →
  `m3_plus_site`, `m4_especie_x_local` → `m4_species_x_site`; the model
  terms use `species` and `site`.
- Whole-recording clips are named `rec_...` instead of `grav_...`.
- Messages, warnings and errors are in English.

## Reading v1.2.0 files

`post_validation()`, `classify_review()`, `calibrate()`,
`read_validations()`, `community_matrices()` and
`build_community_matrices()` read manifests, validation tables and
histories written by v1.2.0 and rename them on reading, so validated data
stay usable.

## Changes in behaviour

- Random draws use `withr::with_seed()`: the draws are those of v1.2.0, and
  the global random number generator is left as it was.
- `suggest_thresholds()` returns an empty table when no reviewed clip has a
  confidence score (whole recordings only); v1.2.0 wrote a row of `NA`.
- The verdict patterns of the review are case-insensitive and only match
  the subfolders below `review_dir`, not the review folder itself.
- A manifest without a `confidence` column is accepted.
- `score_detections()` warns about prediction tables named after a site
  that is not in the calibration, and keeps the site name in the output.
- The random-effects models of the calibration need 'lme4', and the
  package now stops when it is missing instead of letting those fits fail.
- 'av', 'lme4' and 'ggplot2' are suggested packages, needed only to cut
  audio, to fit hierarchical models and to draw the figures.

# birdnet-validation-sampler 1.2.0

- Random sampling modes to estimate false-positive rates (`modo_amostragem`
  `"aleatorio_deteccoes"` and `"aleatorio_gravacoes"`), with the manifest
  columns `modo_amostragem`, `ocasiao_id`, `n_deteccoes_ocasiao` and
  `prob_inclusao`.
