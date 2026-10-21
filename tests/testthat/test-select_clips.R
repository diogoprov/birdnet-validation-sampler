cenarios <- c("top_default", "top_meta", "top_max", "det_file",
              "det_minute_meta", "det_max", "rec_file", "rec_minute",
              "rec_table")

# Manifesto de um cenario, com as mesmas entradas da referencia
manifesto_cenario <- function(nome) {
  pred <- suppressMessages(
    read_selection_tables(file.path(sim_root(), "tabelas")))
  args <- scenario_args(nome)
  suppressMessages(suppressWarnings(
    do.call(select_clips, c(list(detections = pred), args))))
}

for (nm in cenarios) {
  test_that(paste("select_clips() reproduces v1.2.0:", nm), {
    novo <- as_written(manifesto_cenario(nm))
    ref  <- ref_table(nm, "manifesto_clipes.csv") |> dplyr::select(-status)
    expect_identical(names(novo), names(ref))
    expect_identical(novo, ref)
  })
}

# Predicoes brutas >= limiar com ocasiao (arquivo), data e hora, contadas
# direto da tabela simulada, sem passar pelo pacote
candidatas_brutas <- function(limiar, horas = 0:23) {
  pred <- suppressMessages(
    read_selection_tables(file.path(sim_root(), "tabelas")))
  pred |>
    dplyr::filter(confidence >= limiar) |>
    dplyr::mutate(
      occasion_id = tools::file_path_sans_ext(
        basename(gsub("\\\\", "/", begin_path))),
      data = sub("^.*_(\\d{8})_(\\d{6})$", "\\1", occasion_id),
      hora = substr(sub("^.*_(\\d{8})_(\\d{6})$", "\\2", occasion_id), 1, 2)) |>
    dplyr::filter(as.integer(hora) %in% horas)
}

test_that("random_detections keeps every clip of each drawn occasion", {
  for (nm in c("det_file", "det_minute_meta", "det_max")) {
    m <- manifesto_cenario(nm)
    por_ocasiao <- dplyr::count(m, site, species_code, occasion_id,
                                n_detections_occasion)
    expect_equal(por_ocasiao$n, por_ocasiao$n_detections_occasion)
    expect_true(all(m$confidence >= scenario_args(nm)$threshold))
    expect_true(any(por_ocasiao$n > 1))
  }

  # contagem independente: cada ocasiao sorteada tem todas as predicoes
  # >= limiar da tabela bruta, e ha no maximo n_top = 1 por estrato
  m <- manifesto_cenario("det_file")
  bruto <- dplyr::count(candidatas_brutas(0.5), site, species_code,
                        occasion_id, name = "n_bruto")
  obs <- dplyr::count(m, site, species_code, occasion_id) |>
    dplyr::left_join(bruto, by = c("site", "species_code", "occasion_id"))
  expect_equal(obs$n, obs$n_bruto)
  por_estrato <- dplyr::distinct(m, site, species_code, night,
                                 recording_hour, occasion_id) |>
    dplyr::count(site, species_code, night, recording_hour)
  expect_true(all(por_estrato$n == 1))
})

test_that("inclusion_prob follows each design", {
  # top: selecao pelo score, nao probabilistica
  expect_true(all(is.na(manifesto_cenario("top_default")$inclusion_prob)))

  # random_detections sem meta: min(n_top, N) / N, com N ocasioes
  # candidatas por local x especie x noite x hora
  m <- manifesto_cenario("det_file")
  esperado <- candidatas_brutas(0.5) |>
    dplyr::distinct(site, species_code, occasion_id, data, hora) |>
    dplyr::add_count(site, species_code, data, hora, name = "N") |>
    dplyr::transmute(site, species_code, occasion_id, p = 1 / N)
  obs <- dplyr::distinct(m, site, species_code, occasion_id, inclusion_prob) |>
    dplyr::inner_join(esperado, by = c("site", "species_code", "occasion_id"))
  expect_equal(nrow(obs), nrow(dplyr::distinct(m, site, species_code,
                                               occasion_id)))
  expect_equal(obs$inclusion_prob, obs$p)
  expect_true(any(obs$p < 1))

  # random_detections com limite por especie (det_max: n_top = 2, horas
  # 18-23, max_per_species = 4, sem balancear por hora): p = p1 x p2, com
  # p1 = min(2, N) / N (N ocasioes candidatas no estrato local x especie x
  # noite x hora) e p2 = min(4, S) / S (S ocasioes que passam da 1a etapa
  # no local x especie)
  m <- manifesto_cenario("det_max")
  esperado <- candidatas_brutas(0.5, horas = 18:23) |>
    dplyr::distinct(site, species_code, occasion_id, data, hora) |>
    dplyr::add_count(site, species_code, data, hora, name = "N") |>
    dplyr::group_by(site, species_code) |>
    dplyr::mutate(S = sum(pmin(2, N) / N)) |>
    dplyr::ungroup() |>
    dplyr::transmute(site, species_code, occasion_id,
                     p = pmin(2, N) / N * pmin(4, S) / S)
  obs <- dplyr::distinct(m, site, species_code, occasion_id, inclusion_prob) |>
    dplyr::left_join(esperado, by = c("site", "species_code", "occasion_id"))
  expect_equal(obs$inclusion_prob, obs$p)

  p <- manifesto_cenario("det_minute_meta")$inclusion_prob
  expect_true(all(p > 0 & p <= 1))

  # random_recordings: gravacoes sorteadas / gravacoes do local
  for (nm in c("rec_file", "rec_table")) {
    m <- manifesto_cenario(nm)
    n_grav <- table(simulate_recordings_table(sim_root())$local)
    obs <- dplyr::summarise(m, n = dplyr::n_distinct(occasion_id),
                            p = unique(inclusion_prob), .by = site)
    expect_equal(obs$p, as.numeric(obs$n / n_grav[obs$site]))
  }
  # rec_minute: 4 minutos por local entre (gravacoes x 3 minutos de 180 s)
  m <- manifesto_cenario("rec_minute")
  n_grav <- table(simulate_recordings_table(sim_root())$local)
  expect_equal(unique(m$inclusion_prob), unique(4 / (as.numeric(n_grav) * 3)))
  expect_true(all(is.na(m$confidence)))
})

test_that("select_clips() leaves the global RNG untouched", {
  pred <- suppressMessages(
    read_selection_tables(file.path(sim_root(), "tabelas")))
  set.seed(99)
  antes <- .Random.seed
  suppressMessages(select_clips(pred, "random_detections", threshold = 0.5))
  expect_identical(.Random.seed, antes)
})

test_that("random_detections needs a threshold", {
  pred <- suppressMessages(
    read_selection_tables(file.path(sim_root(), "tabelas")))
  expect_error(suppressMessages(select_clips(pred, "random_detections")),
               "threshold")
})
