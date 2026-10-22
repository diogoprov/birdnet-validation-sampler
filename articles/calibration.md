# Calibrating confidence scores

This vignette covers the second stage of sheepdog in detail: turning
BirdNET confidence scores into probabilities that a detection is a true
positive, scoring every detection, and building nightly detection
histories. Each step is run on the example data shipped with the
package.

``` r

library(sheepdog)
library(dplyr)
ex <- system.file("extdata", "example", package = "sheepdog")
```

## Why calibrate

A BirdNET confidence score is a classifier output in \[0, 1\], not a
probability that the detection is correct. The BirdNET authors recommend
converting the scores into probabilities of a true detection (Wood &
Kahl 2024). One way to do so, with a sample of manually validated
detections, is a logistic regression of the verdict on logit(score),
applied, for instance, by Owens et al. (2026).

One curve for all species is rarely enough. The same score can mean
different things for different species, because the score distributions
of true and false detections differ among species, and for the same
species at different sites, because the rate of false detections depends
on background noise and the rate of true ones on how often the species
is present. sheepdog therefore fits hierarchical logistic models in
which the intercept and the slope on logit(score) can vary among species
and among sites.

## The example data

The example data are simulated (`data-raw/make_example_data.R`). Five
anuran species were recorded at four sites over six months, from October
2021 to March 2022. When a species is present, its true detections have
scores drawn from a species-specific Beta distribution. Every species
also produces false positives in every recording, present or not, with
scores drawn from a second species-specific Beta distribution that
overlaps the first. The rate of false positives is multiplied by a site
noise factor (ARA 0.7, BAI 1.0, XAR 1.5, NHE 2.2), and presence varies
with site and season. The same score therefore corresponds to different
probabilities of a true detection among species and sites. The verdicts
of the reviewed clips come from the simulated truth.

The reviewed clips are the `validation_by_clip_<site>.csv` tables
written by
[`post_validation()`](https://provetelab.org/sheepdog/reference/post_validation.md).
[`read_validations()`](https://provetelab.org/sheepdog/reference/read_validations.md)
stacks them, keeps the clips with a positive or negative verdict and a
confidence score, and adds `logit_conf` and the binary response `tp`.

``` r

val_files <- list.files(file.path(ex, "validation"), full.names = TRUE)
val <- read_validations(val_files)
#> 1600 reviewed clips (809 TP / 791 FP) of 5 species at 4 sites.
table(val$site, val$species)
#>      
#>       boa_ran den_nan lep_fus pse_pla sci_nas
#>   ARA      80      80      80      80      80
#>   BAI      80      80      80      80      80
#>   NHE      80      80      80      80      80
#>   XAR      80      80      80      80      80
```

The clips were selected with the `"top"` design (the two highest scores
per site x species x night x hour, at most 80 per site x species).
Precision differs widely among species:

``` r

val |>
  group_by(species) |>
  summarise(clips = n(), precision = mean(tp),
            min_conf = min(confidence), median_conf = median(confidence))
#> # A tibble: 5 × 5
#>   species clips precision min_conf median_conf
#>   <fct>   <int>     <dbl>    <dbl>       <dbl>
#> 1 boa_ran   320     0.875    0.106       0.796
#> 2 den_nan   320     0.706    0.104       0.704
#> 3 lep_fus   320     0.303    0.102       0.404
#> 4 pse_pla   320     0.25     0.148       0.643
#> 5 sci_nas   320     0.394    0.136       0.630
```

## Candidate models

[`calibration_models()`](https://provetelab.org/sheepdog/reference/calibration_models.md)
returns the family of candidate models. All of them are binomial
regressions of `tp` on `logit_conf`. They differ in how the calibration
curve is allowed to vary among species and sites.

``` r

models <- calibration_models()
cat(paste0(names(models), ": ", vapply(models, deparse1, "")), sep = "\n")
#> m0_global: tp ~ logit_conf
#> m1_species_intercept: tp ~ logit_conf + (1 | species)
#> m2_species_slope: tp ~ logit_conf + (logit_conf | species)
#> m3_plus_site: tp ~ logit_conf + (logit_conf | species) + (1 | site)
#> m4_species_x_site: tp ~ logit_conf + (logit_conf | species) + (1 | site:species)
```

- `m0_global`: one curve for all species and sites (a GLM).
- `m1_species_intercept`: species shift the curve along the score axis.
- `m2_species_slope`: species also differ in how steeply the probability
  rises with the score.
- `m3_plus_site`: as m2, plus a site intercept shared by all species.
- `m4_species_x_site`: as m2, plus an intercept for each site x species
  combination. This is the most flexible model.

Models m1 to m4 are binomial GLMMs fitted with
[`lme4::glmer()`](https://rdrr.io/pkg/lme4/man/glmer.html).

## Comparing models by cross-validation

[`compare_calibration_models()`](https://provetelab.org/sheepdog/reference/compare_calibration_models.md)
fits every candidate with k-fold cross-validation and computes the area
under the ROC curve (AUC) on the held-out folds. Folds are stratified
within site x species, so every level appears in both the training and
the test sets. The fold assignment uses a fixed `seed`. Five folds run
in a few seconds on these data.

``` r

cv <- compare_calibration_models(val, models, k_folds = 5)
#> Cross-validation (5 folds) of 5 models...
cv |> select(model, auc_mean, auc_sd)
#> # A tibble: 5 × 3
#>   model                auc_mean auc_sd
#>   <chr>                   <dbl>  <dbl>
#> 1 m4_species_x_site       0.885 0.0181
#> 2 m3_plus_site            0.882 0.0194
#> 3 m2_species_slope        0.872 0.0183
#> 4 m1_species_intercept    0.865 0.0221
#> 5 m0_global               0.804 0.0256
```

The table is ordered by mean AUC. Read the differences between models
together with the spread among folds (`auc_sd`). Here, any species
effect improves on the global model by much more than the fold-to-fold
standard deviation (AUC 0.804 for m0 against 0.865 for m1), and site
effects add a smaller gain (0.885 for m4). The differences among the
hierarchical models are of the same order as `auc_sd`, so their order
can change with `k_folds` or `seed`.

AUC measures discrimination (whether true detections score higher than
false ones), not calibration (whether a predicted probability of 0.9 is
correct nine times in ten). Two models with equal AUC can still give
different probabilities, so the comparison is a first filter, not the
whole decision.

When the leading models are close, a simple heuristic is to keep the
least complex model whose mean AUC is within one standard deviation of
the best one. This is a judgement call, not a rule implemented by the
package:

``` r

complexity <- match(cv$model, names(models))
within_1sd <- cv$auc_mean >= cv$auc_mean[1] - cv$auc_sd[1]
parsimonious <- cv$model[within_1sd][which.min(complexity[within_1sd])]
parsimonious
#> [1] "m2_species_slope"
```

The wrapper
[`calibrate()`](https://provetelab.org/sheepdog/reference/calibrate.md)
takes the first row of the table (m4_species_x_site), whereas the
heuristic retains m2_species_slope. The next sections show what the two
choices imply.

## Fitting the calibration model

[`fit_calibration()`](https://provetelab.org/sheepdog/reference/fit_calibration.md)
fits a model to all the reviewed clips and stores the species and site
levels with it, for
[`score_detections()`](https://provetelab.org/sheepdog/reference/score_detections.md)
and
[`plot_calibration()`](https://provetelab.org/sheepdog/reference/plot_calibration.md).
We fit every candidate, because whether a GLMM is singular is part of
the choice:

``` r

fits <- lapply(models, function(f) fit_calibration(val, f))
#> Warning: Singular fit (boundary) of the calibration model tp ~ logit_conf +
#> (logit_conf | species) + (1 | site:species): a variance component is estimated
#> at zero or a correlation at +-1. Check lme4::VarCorr(fit) and consider a
#> simpler model.
vapply(fits[-1], lme4::isSingular, logical(1))
#> m1_species_intercept     m2_species_slope         m3_plus_site 
#>                FALSE                FALSE                FALSE 
#>    m4_species_x_site 
#>                 TRUE
```

``` r

fit_global <- fits$m0_global
fit_full   <- fits$m4_species_x_site
coef(fit_global)
#> (Intercept)  logit_conf 
#>   -0.749944    1.266749
lme4::fixef(fit_full)
#> (Intercept)  logit_conf 
#>  -0.6271446   1.4722266
lme4::VarCorr(fit_full)
#>  Groups       Name        Std.Dev. Corr  
#>  site:species (Intercept) 0.92155        
#>  species      (Intercept) 0.56566        
#>               logit_conf  0.69987  1.000
```

The site x species intercepts of m4 have a standard deviation of 0.92 on
the logit scale, a large effect: at a given score, the odds of a true
detection differ several-fold among sites for the same species. The fit
is nevertheless singular, which is why
[`fit_calibration()`](https://provetelab.org/sheepdog/reference/fit_calibration.md)
warned above: the correlation between the species intercepts and slopes
is estimated at 1, on the boundary of its range. With 5 species, a
correlation between two random effects is poorly identified. A singular
fit means that the random-effect structure is more complex than the data
can support. The predictions can still be used, but this variance
component should not be interpreted. The singularity lies in the species
term, not in the site x species term that gives m4 its advantage: m2 and
m3 share the same species term and are not singular (in m3 the
correlation is 0.93), and m3 comes close to m4 in the comparison. A
non-singular model within one standard deviation of the best (m2 or m3
here) is a defensible alternative to m4. Fitting m4 without the
correlation (with `(1 | species) + (0 + logit_conf | species)`) would be
a further option, but it is not one of the built-in candidates.

## Calibration curves

[`plot_calibration()`](https://provetelab.org/sheepdog/reference/plot_calibration.md)
draws the calibrated probability against the score, one panel per
species and one line per site. The points give the observed precision of
the reviewed clips in 0.1-wide score bins, sized by the number of clips.
The dashed line marks `p_min`.

``` r

plot_calibration(fit_full, val, p_min = 0.95, model_name = "m4_species_x_site")
```

![](calibration_files/figure-html/unnamed-chunk-11-1.png)

Look for:

- **Flat or shallow curves.** A species whose curve rises slowly, or
  never reaches `p_min`, is poorly separated from its false positives.
  Its calibrated detections should not enter the analyses, or only in a
  sensitivity analysis.
- **Sites that diverge.** A site whose curve lies far from the others
  for the same species may differ in noise, in the number of false
  positives, or in the review. Check its clips before trusting its
  probabilities.
- **Curves that miss the points.** Systematic departures from the
  observed precision indicate lack of fit, usually in the score bins
  with the largest points.
- **Few clips.** Curves supported by small points (few clips per bin)
  are extrapolations. The `"top"` design gives few clips at low scores,
  so the lower part of each curve rests mainly on the shared fixed
  effects.

In the example, all of these appear. `pse_pla` has a shallow curve that
stays well below `p_min` at every site: its false positives overlap its
true detections too much for any score to be reliable. `sci_nas` reaches
`p_min` only at the very top of the score range. For `lep_fus`, the
curve at NHE, the noisiest site, lies far to the right of the others,
and at ARA, the quietest site, to the left.

The practical consequence is the score at which each site x species
reaches `p_min`. Under the global model this score is the same
everywhere:

``` r

grid <- tidyr::expand_grid(
  species    = factor(levels(val$species), levels = levels(val$species)),
  site       = factor(levels(val$site), levels = levels(val$site)),
  confidence = seq(0.10, 0.99, by = 0.01)
) |>
  mutate(logit_conf = qlogis(confidence),
         p_global   = predict(fit_global, newdata = pick(everything()),
                              type = "response"),
         p_full     = predict(fit_full, newdata = pick(everything()),
                              type = "response"))

# lowest score with P(TP) >= 0.95; NA if never reached below 0.99
first_conf <- function(conf, p) {
  if (any(p >= 0.95)) min(conf[p >= 0.95]) else NA_real_
}
thresholds <- grid |>
  group_by(species, site) |>
  summarise(conf_global = first_conf(confidence, p_global),
            conf_full   = first_conf(confidence, p_full),
            .groups = "drop")
thresholds |> print(n = Inf)
#> # A tibble: 20 × 4
#>    species site  conf_global conf_full
#>    <fct>   <fct>       <dbl>     <dbl>
#>  1 boa_ran ARA          0.95      0.72
#>  2 boa_ran BAI          0.95      0.71
#>  3 boa_ran NHE          0.95      0.77
#>  4 boa_ran XAR          0.95      0.8 
#>  5 den_nan ARA          0.95      0.76
#>  6 den_nan BAI          0.95      0.91
#>  7 den_nan NHE          0.95      0.9 
#>  8 den_nan XAR          0.95      0.89
#>  9 lep_fus ARA          0.95      0.8 
#> 10 lep_fus BAI          0.95      0.88
#> 11 lep_fus NHE          0.95      0.97
#> 12 lep_fus XAR          0.95      0.87
#> 13 pse_pla ARA          0.95     NA   
#> 14 pse_pla BAI          0.95     NA   
#> 15 pse_pla NHE          0.95     NA   
#> 16 pse_pla XAR          0.95     NA   
#> 17 sci_nas ARA          0.95      0.97
#> 18 sci_nas BAI          0.95      0.98
#> 19 sci_nas NHE          0.95      0.99
#> 20 sci_nas XAR          0.95      0.99
```

Under m4, the score needed to reach P(TP) \>= 0.95 ranges from 0.71 to
0.99 among site x species combinations, and 4 combinations (pse_pla)
never reach it, against a single threshold of 0.95 under the global
model. A single score threshold, or a single calibration curve, would be
too lenient for some species and sites and too strict for others.

## Scoring every detection

[`score_detections()`](https://provetelab.org/sheepdog/reference/score_detections.md)
reads the complete selection tables (not only the reviewed clips) and
predicts P(TP) for every detection of a calibrated species. The tables
are passed as a vector named by site; the names must match the sites of
the calibration. A site absent from the calibration is scored with the
species effects only, with a warning. The night of a detection is its
recording date, or the day before for recordings that start before
`dawn_hour`.

``` r

sites  <- c("ARA", "XAR", "BAI", "NHE")
tables <- setNames(file.path(ex, "birdnet", sites,
                             "BirdNET_SelectionTable.txt"), sites)
scored <- score_detections(tables, fit_full, min_confidence = 0.1) |>
  suppressMessages()  # one line per site with the number of detections
scored |> select(site, species, night, confidence, p_tp)
#> # A tibble: 5,781 × 5
#>    site  species night    confidence  p_tp
#>    <chr> <fct>   <chr>         <dbl> <dbl>
#>  1 ARA   den_nan 20211001      0.727 0.938
#>  2 ARA   den_nan 20211001      0.670 0.906
#>  3 ARA   den_nan 20211001      0.682 0.914
#>  4 ARA   lep_fus 20211001      0.392 0.419
#>  5 ARA   den_nan 20211001      0.195 0.237
#>  6 ARA   lep_fus 20211001      0.374 0.386
#>  7 ARA   den_nan 20211001      0.497 0.751
#>  8 ARA   pse_pla 20211001      0.528 0.269
#>  9 ARA   den_nan 20211001      0.817 0.972
#> 10 ARA   den_nan 20211001      0.174 0.199
#> # ℹ 5,771 more rows
```

## Nightly detection histories

[`detection_history()`](https://provetelab.org/sheepdog/reference/detection_history.md)
aggregates the scored detections by site x species x night. A detection
is reliable when its calibrated probability is at least `p_min`; the
threshold applies to P(TP), not to the score. A night has a detection
when it holds at least k reliable detections (`min_detections_night`,
the repetition rule). The columns `detection_k1` to `detection_k3` give
the same rule with k = 1, 2 and 3; `detection` uses the chosen k.

``` r

history <- detection_history(scored, p_min = 0.95, min_detections_night = 1)
history
#> # A tibble: 579 × 10
#>    site  species night    n_detections n_reliable p_tp_max detection_k1
#>    <chr> <fct>   <chr>           <int>      <int>    <dbl>        <int>
#>  1 ARA   boa_ran 20211001            1          0   0.436             0
#>  2 ARA   boa_ran 20211016            1          0   0.425             0
#>  3 ARA   boa_ran 20211021            1          0   0.0658            0
#>  4 ARA   boa_ran 20211101           11          5   0.995             1
#>  5 ARA   boa_ran 20211106           11          5   0.996             1
#>  6 ARA   boa_ran 20211111           13          5   0.998             1
#>  7 ARA   boa_ran 20211116           17         12   1.000             1
#>  8 ARA   boa_ran 20211121            6          3   0.999             1
#>  9 ARA   boa_ran 20211201            9          3   0.997             1
#> 10 ARA   boa_ran 20211206            8          3   1.000             1
#> # ℹ 569 more rows
#> # ℹ 3 more variables: detection_k2 <int>, detection_k3 <int>, detection <int>
summarise_history(history) |> print(n = Inf)
#> # A tibble: 20 × 6
#>    site  species nights nights_k1 nights_k2 nights_k3
#>    <chr> <fct>    <int>     <int>     <int>     <int>
#>  1 ARA   boa_ran     28        25        25        25
#>  2 ARA   den_nan     30        30        23        12
#>  3 ARA   lep_fus     25         6         0         0
#>  4 ARA   pse_pla     30         0         0         0
#>  5 ARA   sci_nas     29         0         0         0
#>  6 BAI   boa_ran     30        30        30        26
#>  7 BAI   den_nan     29         8         2         0
#>  8 BAI   lep_fus     29         0         0         0
#>  9 BAI   pse_pla     30         0         0         0
#> 10 BAI   sci_nas     30         0         0         0
#> 11 NHE   boa_ran     30        30        27        23
#> 12 NHE   den_nan     30        15         5         2
#> 13 NHE   lep_fus     30         0         0         0
#> 14 NHE   pse_pla     30         0         0         0
#> 15 NHE   sci_nas     30         0         0         0
#> 16 XAR   boa_ran     28        23        18        14
#> 17 XAR   den_nan     28         8         3         1
#> 18 XAR   lep_fus     27         2         0         0
#> 19 XAR   pse_pla     28         0         0         0
#> 20 XAR   sci_nas     28         0         0         0
```

`nights` counts the nights with any scored detection, and `nights_k1` to
`nights_k3` the nights with a detection under each rule. The gap between
`nights` and `nights_k1` is the number of nights whose detections were
all below `p_min`: nights that a rule on the raw output (any detection
above `min_confidence`) would have counted as detections. Species whose
curves never reach `p_min` have no night with a detection, whatever
their scores.

## Choosing p_min and k

`p_min` and k trade false-positive nights against missed nights. A high
`p_min` with k = 1 accepts a night on one very reliable detection; a
lower `p_min` with k = 2 or 3 requires repeated, moderately reliable
detections. The choice should follow the analysis: occupancy models with
false-positive parameters can tolerate a lenient rule, whereas analyses
with no false-positive component (for example, ordinations of community
matrices) call for a strict one. The sensitivity of the number of nights
with a detection to both settings is cheap to check:

``` r

sensitivity <- lapply(c(0.80, 0.90, 0.95, 0.99), function(p) {
  detection_history(scored, p_min = p) |>
    summarise(p_min = p, k1 = sum(detection_k1), k2 = sum(detection_k2),
              k3 = sum(detection_k3))
}) |>
  bind_rows()
sensitivity
#> # A tibble: 4 × 4
#>   p_min    k1    k2    k3
#>   <dbl> <int> <int> <int>
#> 1  0.8    246   208   182
#> 2  0.9    212   171   143
#> 3  0.95   177   133   103
#> 4  0.99   116    63    36
```

The number of nights with a detection under k = 1 falls from 246 to 116
across this range of `p_min`. If the conclusions of the downstream
analysis change across the range, report the results under more than one
setting.

The same check applies to the choice of model. Scoring with the global
model and comparing the histories shows how many site x species x nights
change, and for which species:

``` r

history_global <- score_detections(tables, fit_global) |>
  suppressMessages() |>
  detection_history(p_min = 0.95)
compare <- inner_join(history, history_global,
                      by = c("site", "species", "night"),
                      suffix = c("_full", "_global"))
compare |>
  group_by(species) |>
  summarise(nights = n(),
            k1_full = sum(detection_k1_full),
            k1_global = sum(detection_k1_global),
            differ_k1 = sum(detection_k1_full != detection_k1_global))
#> # A tibble: 5 × 5
#>   species nights k1_full k1_global differ_k1
#>   <fct>    <int>   <int>     <int>     <int>
#> 1 boa_ran    116     108        32        76
#> 2 den_nan    117      61        12        49
#> 3 lep_fus    111       8         0         8
#> 4 pse_pla    118       0         3         3
#> 5 sci_nas    117       0         4         4
```

The global model changes the history of 140 of 579 site x species x
nights under k = 1. It is too strict for the species with high
precision, whose detections need a lower score than the common
threshold, and it accepts nights for species that have no reliable
detection at all under m4.

## When the global model is enough

The global model is enough when the hierarchical models do not improve
the cross-validated AUC beyond the fold-to-fold variation, when the
species and site curves of a hierarchical model lie close together near
`p_min`, and when the detection histories do not change between models.
None of these holds in the example. With very few species or sites the
variance components are poorly estimated, and a simpler model (a species
effect only, or the global model) is the more defensible choice; with
many species, or species and sites known to differ in noise, the
hierarchical models keep the threshold on P(TP) consistent across them.

## Model checks

Before using calibrated probabilities, check that:

1.  **The GLMM converged.**
    [`fit_calibration()`](https://provetelab.org/sheepdog/reference/fit_calibration.md)
    warns when the refitted model is singular, as it did for m4 above,
    and convergence warnings of
    [`lme4::glmer()`](https://rdrr.io/pkg/lme4/man/glmer.html) are
    passed on.
    [`compare_calibration_models()`](https://provetelab.org/sheepdog/reference/compare_calibration_models.md)
    drops a fold whose fit fails from the mean AUC, warns about it and
    counts it in `n_failed`. Inspect the refitted model directly:

    ``` r

    lme4::isSingular(fit_full)
    #> [1] TRUE
    fit_full@optinfo$conv$lme4$messages
    #> [1] "boundary (singular) fit: see help('isSingular')"
    ```

    Here the only message is the singular fit discussed above; there are
    no convergence warnings. Convergence warnings (as opposed to a
    singular fit) mean the estimates should not be used: simplify the
    random-effect structure, or review more clips.

2.  **The cross-validation supports the choice.** Read `auc_sd` with
    `auc_mean`. Do not prefer a more complex model on a difference
    smaller than the fold-to-fold variation.

3.  **The calibration curves are sensible.** Curves should increase with
    the score, follow the observed precision, and rest on enough clips
    near `p_min`.
    [`calibration_effort()`](https://provetelab.org/sheepdog/reference/calibration_effort.md)
    estimates how many clips per site x species are needed for a stable
    AUC.

The calibration also assumes that, within a score level, the reviewed
clips are representative of all the detections of that species at that
site. The model is conditional on the score, so the `"top"` design,
which oversamples high scores, does not bias it as long as this holds.
It fails if the clips were chosen by another criterion related to
correctness (for example, only clips that sounded clear, or only the
nights of peak activity), or if the reviewed period differs from the
scored one in noise or in species composition.

## The calibrate() wrapper

[`calibrate()`](https://provetelab.org/sheepdog/reference/calibrate.md)
runs the whole stage in one call. It reads the clips, compares the
candidate models, refits the best one by mean AUC, plots the calibration
curves (if ggplot2 is installed), scores every detection, builds the
detection history and writes all the outputs to `output_dir`. It refits
the model with the highest mean AUC; when that refit is singular, as m4
is here, it warns (through
[`fit_calibration()`](https://provetelab.org/sheepdog/reference/fit_calibration.md))
but keeps the model. Read the comparison, `calibration_model.txt` and
the curves it writes before using its output, and refit a simpler model
with
[`fit_calibration()`](https://provetelab.org/sheepdog/reference/fit_calibration.md)
if the comparison supports it.

``` r

out_dir <- file.path(tempdir(), "calibration")
res <- calibrate(validation_files  = val_files,
                 prediction_tables = tables,
                 output_dir        = out_dir,
                 p_min = 0.95, min_detections_night = 1, k_folds = 5) |>
  suppressMessages()
#> Warning: Singular fit (boundary) of the calibration model tp ~ logit_conf +
#> (logit_conf | species) + (1 | site:species): a variance component is estimated
#> at zero or a correlation at +-1. Check lme4::VarCorr(fit) and consider a
#> simpler model.
res$comparison$model[1]  # the model calibrate() refitted
#> [1] "m4_species_x_site"
list.files(out_dir)
#>  [1] "calibrated_detections_ARA.csv" "calibrated_detections_BAI.csv"
#>  [3] "calibrated_detections_NHE.csv" "calibrated_detections_XAR.csv"
#>  [5] "calibration_curves.png"        "calibration_model.rds"        
#>  [7] "calibration_model.txt"         "detection_summary.csv"        
#>  [9] "model_comparison.csv"          "nightly_detection_history.csv"
```

`nightly_detection_history.csv` is the input of the occupancy and
community analyses (see
[`vignette("frognet-workflow")`](https://provetelab.org/sheepdog/articles/frognet-workflow.md)).
Five folds and the example’s 1600 clips run in seconds; a project with
thousands of clips and many species takes longer, and
`effort_curve = TRUE` adds the effort curve.

## References

Owens, G., Wood, C. M., Hunt, T. J., Bussolini, L. T., Kreisl, A.,
Alves, F., & Stojanovic, D. (2026). Passive acoustic monitoring of the
rare orange-bellied parrot: automated detection using BirdNET-based
transfer learning. *bioRxiv*.
<https://doi.org/10.64898/2026.06.01.729442>

Wood, C. M., & Kahl, S. (2024). Guidelines for appropriate use of
BirdNET scores and other detector outputs. *Journal of Ornithology*,
165, 777–782. <https://doi.org/10.1007/s10336-024-02144-5>
