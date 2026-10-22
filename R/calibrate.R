#' Read the validation tables for calibration
#'
#' Stacks the `validation_by_clip.csv` tables of several sites (output of
#' [post_validation()]) and keeps the clips with a positive or negative
#' verdict and a confidence score. Tables written by v1.2.0
#' (`validacao_por_clipe.csv`) are also read. Whole-recording clips of
#' `"random_recordings"` have no confidence and are left out.
#'
#' @param files Paths to the `validation_by_clip.csv` files. Missing files
#'   are skipped with a warning.
#' @param site_map Optional named character vector to fix diverging site
#'   names, as `c(old = "new")`, e.g. `c(BEP2 = "BEP")`.
#'
#' @return A tibble with `site` and `species` (factors; `species` is the
#'   species folder code), `confidence`, `logit_conf` (logit of the
#'   confidence, bounded at 1e-4 and 1 - 1e-4) and `tp` (1 = true
#'   positive, 0 = false positive).
#' @export
read_validations <- function(files, site_map = NULL) {
  val <- map(files, function(f) {
    if (!file.exists(f)) { warning("Not found: ", f); return(NULL) }
    read_csv(f, show_col_types = FALSE, progress = FALSE) |>
      from_legacy()
  }) |>
    list_rbind() |>
    # gravacoes sorteadas (modo "random_recordings") nao tem confidence
    filter(verdict %in% c("positive", "negative"), !is.na(confidence)) |>
    transmute(
      site       = rename_site(site, site_map),
      species    = species_folder,
      confidence = confidence,
      logit_conf = safe_logit(confidence),
      tp         = as.integer(verdict == "positive")
    ) |>
    mutate(across(c(site, species), as.factor))

  if (nrow(val) == 0) stop("No reviewed clip found.")
  message(nrow(val), " reviewed clips (", sum(val$tp), " TP / ",
          sum(val$tp == 0), " FP) of ", n_distinct(val$species),
          " species at ", n_distinct(val$site), " sites.")
  val
}

safe_logit <- function(p) stats::qlogis(pmin(pmax(p, 1e-4), 1 - 1e-4))

rename_site <- function(x, mapa) {
  if (is.null(mapa)) return(x)
  ifelse(x %in% names(mapa), unname(mapa[x]), x)
}

#' Candidate calibration models
#'
#' The family of logistic calibration models compared by
#' [compare_calibration_models()], from a single logistic regression on
#' the logit of the confidence score to a binomial GLMM with random slopes
#' by species and a site x species intercept.
#'
#' The list goes from the simplest to the most complex model; that order is
#' the complexity used by [select_calibration_model()].
#'
#' @param uncorrelated Add `m5_species_x_site_uncorrelated`, the m4
#'   structure without the correlation between the species intercepts and
#'   slopes. It avoids the singular fits of m4 when that correlation is
#'   estimated at +-1. `FALSE` keeps the candidates of 2.0.0.
#'
#' @return A named list of formulas: `m0_global`, `m1_species_intercept`,
#'   `m2_species_slope`, `m3_plus_site`, `m4_species_x_site` and, with
#'   `uncorrelated = TRUE`, `m5_species_x_site_uncorrelated`.
#' @export
calibration_models <- function(uncorrelated = FALSE) {
  modelos <- list(
    m0_global            = tp ~ logit_conf,
    m1_species_intercept = tp ~ logit_conf + (1 | species),
    m2_species_slope     = tp ~ logit_conf + (logit_conf | species),
    m3_plus_site         = tp ~ logit_conf + (logit_conf | species) +
                                (1 | site),
    m4_species_x_site    = tp ~ logit_conf + (logit_conf | species) +
                                (1 | site:species)
  )
  if (uncorrelated) {
    modelos$m5_species_x_site_uncorrelated <-
      tp ~ logit_conf + (1 | species) + (0 + logit_conf | species) +
      (1 | site:species)
  }
  modelos
}

#' Compare calibration models by cross-validation
#'
#' Fits each candidate model with k-fold cross-validation and scores the
#' predicted probabilities on the held-out folds. Folds are stratified
#' within site x species, so every level appears in both the training and
#' the test sets. Models with random effects need the 'lme4' package.
#'
#' The AUC measures discrimination (whether true detections get higher
#' probabilities than false ones). The log-loss and the Brier score are
#' proper scoring rules: they reward probabilities close to the observed
#' outcomes, which is what matters when the probabilities are compared
#' with `p_min` (Gneiting & Raftery 2007, \doi{10.1198/016214506000001437}).
#' The calibration intercept and slope come from a logistic regression of
#' the verdicts on the logit of the predicted probabilities in each test
#' fold: a well calibrated model has intercept 0 and slope 1; a slope below
#' 1 means probabilities too extreme (overfitting).
#'
#' @param validations Table returned by [read_validations()].
#' @param models Named list of model formulas.
#' @param k_folds Number of folds.
#' @param seed Seed of the fold assignment. The global random number
#'   generator is left as it was.
#'
#' @return A tibble with `model`, `formula`, `auc_mean`, `auc_sd`,
#'   `n_failed` (folds whose fit failed, left out of the means),
#'   `logloss_mean`, `logloss_sd`, `brier_mean`, `brier_sd`,
#'   `cal_intercept` and `cal_slope` (means over the folds), `prop_singular`
#'   (share of the fold fits that were singular) and `complexity` (position
#'   of the model in `models`), ordered from the highest mean AUC. Failed
#'   folds also raise a warning.
#' @export
compare_calibration_models <- function(validations,
                                       models = calibration_models(),
                                       k_folds = 5, seed = 2026) {
  need_lme4(models)
  # folds estratificados dentro de cada local x especie
  val <- withr::with_seed(seed, {
    validations |>
      group_by(site, species) |>
      mutate(fold = sample(rep_len(seq_len(k_folds), n()))) |>
      ungroup()
  })

  message("Cross-validation (", k_folds, " folds) of ", length(models),
          " models...")
  vazio <- c(auc = NA_real_, logloss = NA_real_, brier = NA_real_,
             cal_intercept = NA_real_, cal_slope = NA_real_,
             singular = NA_real_)
  map(seq_along(models), function(i) {
    nm <- names(models)[i]
    m <- map(seq_len(k_folds), function(k) {
      treino <- filter(val, fold != k)
      teste  <- filter(val, fold == k)
      fit    <- tryCatch(fit_model(models[[nm]], treino),
                         error = function(e) NULL)
      if (is.null(fit)) return(vazio)
      p <- predict_tp(fit, teste)
      c(auc = auc(teste$tp, p), score_probabilities(teste$tp, p),
        singular = as.numeric(inherits(fit, "merMod") &&
                                 lme4::isSingular(fit)))
    }) |>
      do.call(what = rbind)
    n_falhas <- sum(is.na(m[, "auc"]))
    if (n_falhas > 0) {
      warning(nm, ": the fit failed in ", n_falhas, " of ", k_folds,
              " folds, left out of the mean AUC.", call. = FALSE)
    }
    media <- function(x) mean(x, na.rm = TRUE)
    dp    <- function(x) stats::sd(x, na.rm = TRUE)
    tibble(model = nm, formula = deparse1(models[[nm]]),
           auc_mean = media(m[, "auc"]), auc_sd = dp(m[, "auc"]),
           n_failed = n_falhas,
           logloss_mean = media(m[, "logloss"]), logloss_sd = dp(m[, "logloss"]),
           brier_mean = media(m[, "brier"]), brier_sd = dp(m[, "brier"]),
           cal_intercept = media(m[, "cal_intercept"]),
           cal_slope = media(m[, "cal_slope"]),
           prop_singular = media(m[, "singular"]),
           complexity = i)
  }) |>
    list_rbind() |>
    arrange(desc(auc_mean))
}

# Log-loss, Brier e intercepto/inclinacao de calibracao de probabilidades
# previstas p para os vereditos tp (0/1)
score_probabilities <- function(tp, p) {
  p  <- pmin(pmax(p, 1e-6), 1 - 1e-6)
  lp <- stats::qlogis(p)
  inclinacao <- tryCatch(
    unname(stats::coef(stats::glm(tp ~ lp, family = stats::binomial))[2]),
    error = function(e) NA_real_, warning = function(w) NA_real_)
  intercepto <- tryCatch(
    unname(stats::coef(stats::glm(tp ~ 1 + offset(lp),
                                  family = stats::binomial))[1]),
    error = function(e) NA_real_, warning = function(w) NA_real_)
  c(logloss = -mean(tp * log(p) + (1 - tp) * log(1 - p)),
    brier = mean((p - tp)^2),
    cal_intercept = intercepto, cal_slope = inclinacao)
}

#' Select the calibration model
#'
#' Picks a model from the table of [compare_calibration_models()].
#'
#' * `"best_auc"`: the model with the highest mean AUC (the rule of
#'   [calibrate()] in 2.x).
#' * `"one_se_logloss"`: among the models whose mean log-loss is within one
#'   standard error (`logloss_sd / sqrt(k_folds)`) of the lowest, the
#'   simplest (lowest `complexity`); models singular in most folds are left
#'   out, unless all are, which raises a warning. The log-loss rewards
#'   correct probabilities, not only their ranking, and the one-standard-
#'   error rule prefers the simpler model when the data cannot tell the
#'   candidates apart. This rule will be the default of [calibrate()] in
#'   3.0.0.
#'
#' @param comparison Table returned by [compare_calibration_models()].
#' @param rule Selection rule.
#' @param k_folds Number of folds of the comparison (for the standard
#'   error).
#'
#' @return The name of the selected model.
#' @export
select_calibration_model <- function(comparison,
                                     rule = c("best_auc", "one_se_logloss"),
                                     k_folds = 5) {
  rule <- match.arg(rule)
  if (rule == "best_auc") {
    return(comparison$model[which.max(comparison$auc_mean)])
  }
  cand <- filter(comparison, !is.na(logloss_mean))
  regulares <- filter(cand, prop_singular <= 0.5)
  if (nrow(regulares) == 0) {
    warning("Every candidate model is singular in most folds; selecting ",
            "among all of them.", call. = FALSE)
  } else {
    cand <- regulares
  }
  melhor <- cand[which.min(cand$logloss_mean), ]
  limite <- melhor$logloss_mean + melhor$logloss_sd / sqrt(k_folds)
  cand |>
    filter(logloss_mean <= limite) |>
    arrange(complexity) |>
    pull(model) |>
    first()
}

#' Fit the calibration model
#'
#' Fits a calibration model to all the reviewed clips. The species and
#' site levels of `validations` are stored with the model, so that
#' [score_detections()] can score new detections.
#'
#' @inheritParams compare_calibration_models
#' @param formula Model formula, usually the best one of
#'   [compare_calibration_models()].
#'
#' A model with random effects whose fit is singular (a variance estimated
#' at zero or a correlation at +-1) raises a warning: the fixed effects and
#' the predictions can still be used, but the variance components on the
#' boundary should not be interpreted, and a simpler model may predict as
#' well. Check them with `lme4::VarCorr()`.
#'
#' @return A `glm` (no random effects) or `glmerMod` model, with the
#'   attribute `sheepdog_levels` (the species and site levels), used by
#'   [score_detections()] and [plot_calibration()].
#' @export
fit_calibration <- function(validations, formula) {
  fit <- fit_model(formula, validations)
  if (inherits(fit, "merMod") && lme4::isSingular(fit)) {
    warning("Singular fit (boundary) of the calibration model ",
            deparse1(formula), ": a variance component is estimated at ",
            "zero or a correlation at +-1. Check lme4::VarCorr(fit) and ",
            "consider a simpler model.", call. = FALSE)
  }
  attr(fit, "sheepdog_levels") <- list(species = levels(validations$species),
                                       site    = levels(validations$site))
  fit
}

# Formula com efeitos aleatorios? (barra "|" da sintaxe do lme4; o lme4
# fica em Suggests, entao nao da para usar lme4::findbars() aqui)
has_random_effects <- function(formula) {
  grepl("|", deparse1(formula), fixed = TRUE)
}

# Exige o lme4 antes de ajustes protegidos por tryCatch(), que de outro
# modo virariam NA em silencio
need_lme4 <- function(formulas) {
  if (any(map_lgl(formulas, has_random_effects))) {
    require_suggested("lme4", "to fit calibration models with random effects")
  }
}

# Niveis de especie e local guardados por fit_calibration()
fit_levels <- function(fit) {
  niveis <- attr(fit, "sheepdog_levels")
  if (is.null(niveis)) stop("`fit` must come from fit_calibration().")
  niveis
}

# Ajusta glm (sem efeitos aleatorios) ou glmer
fit_model <- function(formula, dados) {
  if (!has_random_effects(formula)) {
    stats::glm(formula, data = dados, family = stats::binomial)
  } else {
    require_suggested("lme4", "to fit calibration models with random effects")
    suppressMessages(lme4::glmer(
      formula, data = dados, family = stats::binomial,
      control = lme4::glmerControl(optimizer = "bobyqa",
                                   optCtrl = list(maxfun = 1e5))))
  }
}

# P(TP) prevista; niveis novos de especie/local usam so os efeitos fixos
predict_tp <- function(modelo, dados) {
  if (inherits(modelo, "merMod")) {
    stats::predict(modelo, newdata = dados, type = "response",
                   allow.new.levels = TRUE)
  } else {
    stats::predict(modelo, newdata = dados, type = "response")
  }
}

auc <- function(tp, p) {
  as.numeric(pROC::auc(pROC::roc(tp, p, quiet = TRUE)))
}

#' Effort curve of the calibration
#'
#' How many reviewed clips per site x species are needed to calibrate
#' well? For each training size, draws that many clips per cell (keeping
#' at least five for testing), fits the model and computes the AUC on the
#' remaining clips. Repetitions with fewer than 50 test clips, or whose
#' fit fails, are dropped.
#'
#' Cells with fewer than `n_train + 5` clips contribute all but five of
#' their clips, so the training size actually used can be below
#' `n_train`; it is reported in `n_train_mean`, with a warning. The test
#' set shrinks as `n_train` grows (`n_test_mean`), which widens `auc_sd`.
#'
#' @inheritParams fit_calibration
#' @param n_train Training sizes per site x species.
#' @param n_reps Repetitions per training size.
#' @param seed Seed of the draws. The global random number generator is
#'   left as it was.
#'
#' @return A tibble with `n_per_cell` (the requested training size),
#'   `auc_mean`, `auc_sd`, `n_train_mean` (mean clips per cell actually
#'   used for training), `n_test_mean` (mean size of the test set) and
#'   `n_failed` (repetitions dropped).
#' @export
calibration_effort <- function(validations, formula,
                               n_train = c(5, 10, 15, 20, 25, 30),
                               n_reps = 50, seed = 2026) {
  need_lme4(list(formula))
  menor <- min(count(validations, site, species)$n)
  acima <- n_train[n_train > menor - 5]
  if (length(acima) > 0) {
    warning("n_train = ", paste(acima, collapse = ", "), " exceeds the ",
            "smallest site x species cell (", menor, " clips) minus the 5 ",
            "kept for testing; see n_train_mean for the size actually used.",
            call. = FALSE)
  }
  message("Effort curve (", n_reps, " repetitions per n)...")
  withr::with_seed(seed, {
    map(n_train, function(n_treino) {
      reps <- map(seq_len(n_reps), function(r) {
        amostra <- validations |>
          group_by(site, species) |>
          mutate(.treino = seq_len(n()) %in%
                   sample(seq_len(n()), min(n_treino, max(n() - 5, 1)))) |>
          ungroup()
        treino <- filter(amostra, .treino)
        teste  <- filter(amostra, !.treino)
        n_cel  <- nrow(treino) / n_distinct(treino$site, treino$species)
        falha  <- c(auc = NA_real_, n_train = n_cel, n_test = nrow(teste))
        if (nrow(teste) < 50) return(falha)
        fit <- tryCatch(fit_model(formula, treino), error = function(e) NULL)
        if (is.null(fit)) return(falha)
        c(auc = auc(teste$tp, predict_tp(fit, teste)), n_train = n_cel,
          n_test = nrow(teste))
      }) |>
        do.call(what = rbind)
      tibble(n_per_cell = n_treino,
             auc_mean = mean(reps[, "auc"], na.rm = TRUE),
             auc_sd = stats::sd(reps[, "auc"], na.rm = TRUE),
             n_train_mean = mean(reps[, "n_train"]),
             n_test_mean = mean(reps[, "n_test"]),
             n_failed = sum(is.na(reps[, "auc"])))
    }) |>
      list_rbind()
  })
}

#' Score every detection with the calibration model
#'
#' Reads the complete BirdNET selection tables (not only the reviewed
#' clips) and predicts, for each detection, the probability that it is a
#' true positive. Only species present in the calibration are scored. The
#' night of each detection is its recording date, or the day before for
#' recordings that start before `dawn_hour`.
#'
#' @param tables Named character vector of selection-table paths, named by
#'   site (the site names of the calibration).
#' @param fit Model returned by [fit_calibration()].
#' @param min_confidence Detections below this confidence are not scored.
#' @param dawn_hour Recordings that start before this hour belong to the
#'   night before.
#'
#' @return A tibble with `site`, `species`, `date`, `night`, `hour`,
#'   `confidence`, `p_tp`, `begin_path` and `file_offset`.
#' @export
score_detections <- function(tables, fit, min_confidence = 0.1,
                             dawn_hour = 12) {
  niveis <- fit_levels(fit)
  novos <- setdiff(names(tables), niveis$site)
  if (length(novos) > 0) {
    warning("Site(s) not in the calibration, scored with the species ",
            "effects only: ", paste(novos, collapse = ", "))
  }
  imap(tables, function(caminho, loc) {
    if (!file.exists(caminho)) {
      warning("Table not found for ", loc, ": ", caminho)
      return(NULL)
    }
    message("Scoring ", loc, " (", caminho, ")...")
    tb <- read_tsv(caminho, show_col_types = FALSE, progress = FALSE,
                   col_select = c(`Species Code`, Confidence,
                                  `Begin Path`, `File Offset (s)`))
    names(tb) <- c("species_code", "confidence", "begin_path", "file_offset")
    m <- str_match(basename(tb$begin_path), "(\\d{8})_(\\d{6})")
    tb <- tb |>
      mutate(
        species = folder_name(species_code),
        date    = m[, 2],
        hour    = as.integer(str_sub(m[, 3], 1, 2)),
        night   = if_else(hour < dawn_hour,
                          format(as.Date(date, "%Y%m%d") - 1, "%Y%m%d"),
                          date),
        site    = loc
      ) |>
      filter(confidence >= min_confidence)

    fora <- sum(!tb$species %in% niveis$species)
    tb <- filter(tb, species %in% niveis$species)
    message("  ", nrow(tb), " detections of calibrated species (", fora,
            " of species NOT calibrated were dropped).")
    if (nrow(tb) == 0) return(NULL)

    tb |>
      mutate(logit_conf = safe_logit(confidence),
             species = factor(species, levels = niveis$species),
             site    = factor(site, levels = niveis$site),
             p_tp    = predict_tp(fit, pick(everything())),
             # local fora da calibracao vira NA no fator: guarda o nome
             site    = loc) |>
      select(site, species, date, night, hour, confidence, p_tp,
             begin_path, file_offset)
  }) |>
    compact() |>
    list_rbind()
}

#' Nightly detection history
#'
#' Aggregates the scored detections by site x species x night. A night has
#' a detection when at least `min_detections_night` detections have a
#' calibrated probability >= `p_min`; the columns `detection_k1` to
#' `detection_k3` give the same rule with k = 1, 2 and 3, as a
#' sensitivity analysis.
#'
#' @param scored Table returned by [score_detections()].
#' @param p_min Threshold on the calibrated probability (not on the
#'   confidence score).
#' @param min_detections_night Repetition rule: minimum number of reliable
#'   detections for a night with detection.
#'
#' @return A tibble with `site`, `species`, `night`, `n_detections`,
#'   `n_reliable`, `p_tp_max`, `detection_k1`, `detection_k2`,
#'   `detection_k3` and `detection`.
#' @export
detection_history <- function(scored, p_min = 0.95,
                              min_detections_night = 1) {
  scored |>
    group_by(site, species, night) |>
    summarise(
      n_detections = n(),
      n_reliable   = sum(p_tp >= p_min),
      p_tp_max     = max(p_tp),
      detection_k1 = as.integer(n_reliable >= 1),
      detection_k2 = as.integer(n_reliable >= 2),
      detection_k3 = as.integer(n_reliable >= 3),
      .groups = "drop"
    ) |>
    mutate(detection = as.integer(n_reliable >= min_detections_night))
}

#' Summarise the detection history by site and species
#'
#' @param history Table returned by [detection_history()].
#'
#' @return A tibble with `site`, `species`, `nights` (nights with any
#'   scored detection) and `nights_k1` to `nights_k3` (nights with
#'   detection under each repetition rule).
#' @export
summarise_history <- function(history) {
  history |>
    group_by(site, species) |>
    summarise(nights = n(),
              nights_k1 = sum(detection_k1), nights_k2 = sum(detection_k2),
              nights_k3 = sum(detection_k3), .groups = "drop")
}

#' Plot the calibration curves
#'
#' Calibrated probability of a true detection against the confidence
#' score, one panel per species and one line per site, with the observed
#' precision by confidence bin as points. Needs the 'ggplot2' package.
#'
#' @inheritParams compare_calibration_models
#' @inheritParams score_detections
#' @inheritParams detection_history
#' @param model_name Name shown in the subtitle.
#'
#' @return A ggplot object.
#' @export
plot_calibration <- function(fit, validations, min_confidence = 0.1,
                             p_min = 0.95, model_name = "") {
  require_suggested("ggplot2", "to plot the calibration curves")
  niveis <- fit_levels(fit)
  grade <- expand_grid(
    species    = factor(niveis$species, levels = niveis$species),
    site       = factor(niveis$site, levels = niveis$site),
    confidence = seq(min_confidence, 0.99, by = 0.01)
  ) |>
    mutate(logit_conf = safe_logit(confidence),
           p_tp = predict_tp(fit, pick(everything())))

  obs_faixa <- validations |>
    mutate(faixa = pmin(floor(confidence * 10) / 10 + 0.05, 0.95)) |>
    group_by(species, site, faixa) |>
    summarise(prec = mean(tp), n = n(), .groups = "drop")

  ggplot2::ggplot(grade, ggplot2::aes(confidence, p_tp, colour = site)) +
    ggplot2::geom_hline(yintercept = p_min, linetype = "dashed",
                        colour = "grey50") +
    ggplot2::geom_line(linewidth = 0.5) +
    ggplot2::geom_point(data = obs_faixa,
                        ggplot2::aes(faixa, prec, size = n, colour = site),
                        alpha = 0.4) +
    ggplot2::scale_size_continuous(range = c(0.5, 3),
                                   name = "reviewed clips") +
    ggplot2::facet_wrap(~ species) +
    ggplot2::labs(x = "BirdNET confidence",
                  y = "Calibrated P(true detection)",
                  title = "Score-to-probability calibration, by species and site",
                  subtitle = paste0("Model: ", model_name,
                                    " | dashed line: p_min = ", p_min)) +
    ggplot2::theme_minimal(base_size = 10)
}

#' Calibrate confidence scores and build detection histories
#'
#' Runs the whole calibration stage: reads the reviewed clips, compares the
#' candidate models by cross-validation, refits the best one to all the
#' clips, optionally draws the effort curve, scores every detection of the
#' complete selection tables and builds the nightly detection history.
#' Writes to `output_dir`:
#' * `model_comparison.csv` ([compare_calibration_models()]);
#' * `calibration_model.rds` and `calibration_model.txt` (the refitted
#'   best model and its summary);
#' * `calibration_curves.png` ([plot_calibration()]), when 'ggplot2' is
#'   installed;
#' * `effort_curve.csv` ([calibration_effort()]), when `effort_curve` is
#'   `TRUE`;
#' * `calibrated_detections_<site>.csv`, one per site
#'   ([score_detections()]);
#' * `nightly_detection_history.csv` ([detection_history()]);
#' * `detection_summary.csv` ([summarise_history()]).
#'
#' The model is chosen by [select_calibration_model()] with the rule
#' `select`: the highest mean AUC by default, or the simplest model within
#' one standard error of the lowest log-loss, leaving out singular fits
#' (`"one_se_logloss"`, the default from 3.0.0). When the refit is singular,
#' [fit_calibration()] warns; read `calibration_model.txt` and the
#' comparison before using the probabilities.
#'
#' Converting BirdNET confidence scores into probabilities is recommended
#' by the BirdNET authors (Wood & Kahl 2024, \doi{10.1007/s10336-024-02144-5});
#' calibration by logistic regression on logit(score) is applied, for
#' instance, by Owens et al. (2026, \doi{10.64898/2026.06.01.729442}).
#' This function extends that approach with a hierarchical multi-species
#' structure. This is the function form of the v1.2.0 script
#' `calibracao.R`.
#'
#' @param validation_files Paths to the `validation_by_clip.csv` files of
#'   the sites (v1.2.0 `validacao_por_clipe.csv` files are also read).
#' @param prediction_tables Named character vector of the complete
#'   selection tables, named by site.
#' @param output_dir Output folder; created if needed. The calibrated
#'   detections of a large project can take hundreds of MB.
#' @inheritParams read_validations
#' @inheritParams score_detections
#' @inheritParams detection_history
#' @inheritParams compare_calibration_models
#' @param select Rule to choose the model; see
#'   [select_calibration_model()].
#' @param uncorrelated Include the m4 variant without the species
#'   intercept-slope correlation among the candidates; see
#'   [calibration_models()].
#' @param effort_curve Draw the effort curve (slow).
#' @param effort_n,effort_reps Training sizes and repetitions of the
#'   effort curve.
#'
#' @return A list with `comparison`, `fit`, `effort` (or `NULL`), `scored`
#'   and `history`, invisibly.
#' @export
calibrate <- function(validation_files, prediction_tables, output_dir,
                      site_map = NULL, min_confidence = 0.1, p_min = 0.95,
                      min_detections_night = 1, dawn_hour = 12,
                      k_folds = 5,
                      select = c("best_auc", "one_se_logloss"),
                      uncorrelated = FALSE, effort_curve = FALSE,
                      effort_n = c(5, 10, 15, 20, 25, 30),
                      effort_reps = 50, seed = 2026) {
  select <- match.arg(select)
  val <- read_validations(validation_files, site_map)
  modelos <- calibration_models(uncorrelated)

  cv <- compare_calibration_models(val, modelos, k_folds, seed)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  write_csv(cv, file.path(output_dir, "model_comparison.csv"))
  melhor <- select_calibration_model(cv, select, k_folds)
  message("Selected model (", select, "): ", melhor)

  fit_final <- fit_calibration(val, modelos[[melhor]])
  saveRDS(fit_final, file.path(output_dir, "calibration_model.rds"))
  utils::capture.output(summary(fit_final),
                        file = file.path(output_dir, "calibration_model.txt"))

  if (requireNamespace("ggplot2", quietly = TRUE)) {
    g <- plot_calibration(fit_final, val, min_confidence, p_min, melhor)
    ggplot2::ggsave(file.path(output_dir, "calibration_curves.png"), g,
                    width = 13, height = 9, dpi = 200, bg = "white")
  } else {
    message("Package 'ggplot2' not installed: calibration_curves.png was ",
            "not drawn.")
  }

  esforco <- NULL
  if (isTRUE(effort_curve)) {
    esforco <- calibration_effort(val, modelos[[melhor]], effort_n,
                                  effort_reps, seed)
    write_csv(esforco, file.path(output_dir, "effort_curve.csv"))
  }

  pontuadas <- score_detections(prediction_tables, fit_final,
                                min_confidence, dawn_hour)
  historico <- NULL
  if (nrow(pontuadas) > 0) {
    walk(split(pontuadas, pontuadas$site, drop = TRUE), function(d) {
      write_csv(d, file.path(output_dir, paste0("calibrated_detections_",
                                                d$site[1], ".csv")))
    })
    historico <- detection_history(pontuadas, p_min, min_detections_night)
    write_csv(historico,
              file.path(output_dir, "nightly_detection_history.csv"))
    write_csv(summarise_history(historico),
              file.path(output_dir, "detection_summary.csv"))
    message("Nights with a reliable detection (p_tp >= ", p_min, "): ",
            sum(historico$detection_k1), " (k = 1), ",
            sum(historico$detection_k2), " (k = 2), ",
            sum(historico$detection_k3), " (k = 3).")
  }

  message("Done! Outputs in ", output_dir,
          "\nnightly_detection_history.csv is the input of the analyses; ",
          "the column 'detection' uses k = ", min_detections_night,
          "; detection_k1/k2/k3 give the sensitivity to the rule.")
  invisible(list(comparison = cv, fit = fit_final, effort = esforco,
                 scored = pontuadas, history = historico))
}
