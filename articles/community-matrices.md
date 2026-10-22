# From detections to community analyses

Stage 3 of sheepdog turns the calibrated nightly detection history into
site x month community matrices for multivariate analyses. This vignette
runs that stage on the example data shipped with the package and closes
with an illustrative ordination.

``` r

library(sheepdog)
```

## The calibrated detection history

The example history is the output of
[`calibrate()`](https://provetelab.org/sheepdog/reference/calibrate.md)
on simulated BirdNET predictions for four sites, five species and six
months (October 2021 to March 2022), with five recorded nights per site
x month, except for one recorder failure. In the simulation, occupancy
is seasonal (higher in the rainy months, November to February) and
differs among sites and species; the false-positive scores overlap those
of true detections, at rates that vary among species and sites
(`data-raw/make_example_data.R`).

``` r

ex <- system.file("extdata", "example", package = "sheepdog")
history_file <- file.path(ex, "nightly_detection_history.csv")
history <- readr::read_csv(history_file, show_col_types = FALSE,
                           col_types = readr::cols(night = "c"))
history
#> # A tibble: 579 × 10
#>    site  species night    n_detections n_reliable p_tp_max detection_k1
#>    <chr> <chr>   <chr>           <dbl>      <dbl>    <dbl>        <dbl>
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
#> # ℹ 3 more variables: detection_k2 <dbl>, detection_k3 <dbl>, detection <dbl>
```

The history covers 4 sites (ARA, BAI, NHE, XAR) and 5 species (boa_ran,
den_nan, lep_fus, pse_pla, sci_nas). Each row is a site x species x
night. `n_reliable` counts the detections whose calibrated probability
of being a true positive reached `p_min` in
[`calibrate()`](https://provetelab.org/sheepdog/reference/calibrate.md);
`detection_k1` to `detection_k3` flag nights with at least one, two or
three such detections.

## Why the entry rule must be strict

Occupancy models with false positives include an observation layer that
absorbs misidentifications, provided that part of the detections are
confirmed (see
[`vignette("crywolf-integration")`](https://provetelab.org/sheepdog/articles/crywolf-integration.md)).
Dissimilarity indices and ordinations have no such layer: a single false
positive becomes a species “present” in a sample and contributes
directly to beta diversity.
[`community_matrices()`](https://provetelab.org/sheepdog/reference/community_matrices.md)
therefore applies three filters.

- **Repetition rule (`k_min`).** A species counts as detected on a night
  only when it had at least `k_min` reliable detections that night
  (column `detection_k<k_min>`). An isolated high-probability detection
  is more likely to be an error than repeated ones.
- **Core species.** Only species whose calibration is reliable at every
  site enter the matrix. If the classifier has lower recall, or a poorer
  calibration, at some sites, the resulting differences in detection
  would appear as artefactual turnover among sites.
- **Minimum effort (`min_nights_month`).** Each cell is the frequency of
  nights with detection, standardised by effort (nights with detection /
  nights recorded at that site x month). Cells with fewer recorded
  nights than `min_nights_month` give unstable frequencies and are
  dropped.

## Choosing the core species

The choice of core species is made by the user, from the calibration
diagnostics written by
[`calibrate()`](https://provetelab.org/sheepdog/reference/calibrate.md)
(e.g. `calibration_curves.png`); the package does not make it
automatically.
[`summarise_history()`](https://provetelab.org/sheepdog/reference/summarise_history.md)
gives a complementary view: the number of nights with a reliable
detection per site and species under each repetition rule (shown below
for `k_min = 1`).

``` r

by_site <- summarise_history(history)
by_site |>
  dplyr::select(site, species, nights_k1) |>
  tidyr::pivot_wider(names_from = site, values_from = nights_k1)
#> # A tibble: 5 × 5
#>   species   ARA   BAI   NHE   XAR
#>   <chr>   <dbl> <dbl> <dbl> <dbl>
#> 1 boa_ran    25    30    30    23
#> 2 den_nan    30     8    15     8
#> 3 lep_fus     6     0     0     2
#> 4 pse_pla     0     0     0     0
#> 5 sci_nas     0     0     0     0
```

Species with no reliable detection anywhere (pse_pla, sci_nas) are cases
in which calibrated probabilities rarely reach `p_min`, because their
false-positive scores overlap those of true detections; in the
simulation every species has a non-zero probability of occupancy at
every site. Species reliably detected at some sites only (lep_fus) are
the case the core rule targets: their absence from a site may reflect
the classifier rather than the community. Here the core species are
taken as those with at least one night with a reliable detection at
every site (boa_ran, den_nan). This is a convenient proxy for the
example; with real data the decision rests on the calibration
diagnostics, and a species that is truly absent from some sites should
not be excluded on this criterion alone.

``` r

core <- by_site |>
  dplyr::summarise(all_sites = all(nights_k1 > 0), .by = species) |>
  dplyr::filter(all_sites) |>
  dplyr::pull(species) |>
  sort()
core
#> [1] "boa_ran" "den_nan"
```

## Building the matrices

``` r

mats <- community_matrices(history, core_species = core, k_min = 2,
                           min_nights_month = 5)
names(mats)
#> [1] "frequency" "counts"    "effort"
```

The effort table lists the recorded nights per site x month and whether
the cell entered the matrices.

``` r

mats$effort
#> # A tibble: 24 × 4
#>    site  month   n_nights_recorded included
#>    <chr> <chr>               <int> <lgl>   
#>  1 ARA   2021-10                 5 TRUE    
#>  2 ARA   2021-11                 5 TRUE    
#>  3 ARA   2021-12                 5 TRUE    
#>  4 ARA   2022-01                 5 TRUE    
#>  5 ARA   2022-02                 5 TRUE    
#>  6 ARA   2022-03                 5 TRUE    
#>  7 BAI   2021-10                 5 TRUE    
#>  8 BAI   2021-11                 5 TRUE    
#>  9 BAI   2021-12                 5 TRUE    
#> 10 BAI   2022-01                 5 TRUE    
#> # ℹ 14 more rows
mats$effort |> dplyr::filter(!included)
#> # A tibble: 1 × 4
#>   site  month   n_nights_recorded included
#>   <chr> <chr>               <int> <lgl>   
#> 1 XAR   2021-10                 3 FALSE
```

Of the 24 site x month cells, 23 entered the matrices. The cell dropped
by `min_nights_month = 5` is XAR in 2021-10 (3 nights), the month of the
simulated recorder failure; it remains listed in the effort table with
`included = FALSE`. Effort is approximated by the number of distinct
nights that appear in the history of the site for any species, which is
adequate when detections are dense, as here.

The count matrix holds the number of nights with detection, and the
frequency matrix divides it by the recorded nights:

``` r

mats$counts
#> # A tibble: 23 × 5
#>    site  month   n_nights_recorded boa_ran den_nan
#>    <chr> <chr>               <int>   <int>   <int>
#>  1 ARA   2021-10                 5       0       2
#>  2 ARA   2021-11                 5       5       4
#>  3 ARA   2021-12                 5       5       3
#>  4 ARA   2022-01                 5       5       4
#>  5 ARA   2022-02                 5       5       5
#>  6 ARA   2022-03                 5       5       5
#>  7 BAI   2021-10                 5       5       0
#>  8 BAI   2021-11                 5       5       0
#>  9 BAI   2021-12                 5       5       1
#> 10 BAI   2022-01                 5       5       0
#> # ℹ 13 more rows
mats$frequency
#> # A tibble: 23 × 5
#>    site  month   n_nights_recorded boa_ran den_nan
#>    <chr> <chr>               <int>   <dbl>   <dbl>
#>  1 ARA   2021-10                 5       0     0.4
#>  2 ARA   2021-11                 5       1     0.8
#>  3 ARA   2021-12                 5       1     0.6
#>  4 ARA   2022-01                 5       1     0.8
#>  5 ARA   2022-02                 5       1     1  
#>  6 ARA   2022-03                 5       1     1  
#>  7 BAI   2021-10                 5       1     0  
#>  8 BAI   2021-11                 5       1     0  
#>  9 BAI   2021-12                 5       1     0.2
#> 10 BAI   2022-01                 5       1     0  
#> # ℹ 13 more rows
```

## Sensitivity to the repetition rule

The repetition rule trades false positives against missed detections.
The mean frequency of each core species across cells shows how the
matrix changes with `k_min`:

``` r

sens <- lapply(1:3, function(k) {
  community_matrices(history, core, k_min = k)$frequency |>
    dplyr::summarise(dplyr::across(dplyr::all_of(core), mean)) |>
    dplyr::mutate(k_min = k, .before = 1)
}) |>
  dplyr::bind_rows()
sens
#> # A tibble: 3 × 3
#>   k_min boa_ran den_nan
#>   <int>   <dbl>   <dbl>
#> 1     1   0.939   0.530
#> 2     2   0.870   0.287
#> 3     3   0.765   0.130
```

From `k_min = 1` to `3`, the mean frequency of boa_ran falls by 19%,
whereas that of den_nan falls by 75%. The rule therefore acts unevenly
among species, and its effect on the ordination should be reported.
`k_min = 2` is the default.

## Writing the matrices to disk

[`build_community_matrices()`](https://provetelab.org/sheepdog/reference/build_community_matrices.md)
is the wrapper that reads `nightly_detection_history.csv`, calls
[`community_matrices()`](https://provetelab.org/sheepdog/reference/community_matrices.md)
and writes the frequency and count matrices and the effort table as CSV
files:

``` r

out <- file.path(tempdir(), "community_matrices")
mats <- build_community_matrices(history_file, out, core_species = core,
                                 k_min = 2, min_nights_month = 5)
#> Matrix: 23 rows (site x month) x 2 species | rule k >= 2
#> Effort: 23 site x month cells included; 1 dropped for having < 5 recorded nights (see effort_site_month.csv)
#> Files in: /tmp/RtmpZvY9vW/community_matrices
list.files(out)
#> [1] "count_matrix_site_month_k2.csv"     "effort_site_month.csv"             
#> [3] "frequency_matrix_site_month_k2.csv"
```

## An illustrative ordination

The example has only 4 sites, six months and 2 core species, so the
ordination below illustrates the workflow; it does not support
inference. With so few species, the ordination adds little to a plot of
the raw frequencies. It uses the **vegan** package, which is suggested
but not required by sheepdog.

The dissimilarity is Bray–Curtis on the frequency matrix, which retains
the quantitative information of the frequencies; Jaccard on incidence
would discard it. \[CITAR: properties of Bray–Curtis and Jaccard for
frequency data in community ordination\] Samples in which no core
species was detected have undefined Bray–Curtis dissimilarity and must
be removed first.

``` r

freq <- mats$frequency |>
  dplyr::mutate(
    season = ifelse(substr(month, 6, 7) %in% c("11", "12", "01", "02"),
                    "rainy", "dry"),
    label  = paste(site, month)
  )
Y <- as.matrix(freq[, core])
rownames(Y) <- freq$label
empty <- rowSums(Y) == 0
freq$label[empty] # samples removed
freq_ord <- freq[!empty, ]
Y <- Y[!empty, , drop = FALSE]
d <- vegan::vegdist(Y, method = "bray")
```

A principal coordinates analysis (PCoA) on the dissimilarity matrix:

``` r

pcoa <- vegan::wcmdscale(d, eig = TRUE)
expl <- pcoa$eig[pcoa$eig > 0] / sum(pcoa$eig[pcoa$eig > 0])
round(100 * expl[1:2], 1)
sum(pcoa$eig < 0) # negative eigenvalues
scores_pcoa <- data.frame(freq_ord[, c("site", "month", "season")],
                          PCo1 = pcoa$points[, 1], PCo2 = pcoa$points[, 2])
```

Bray–Curtis is not Euclidean, so some eigenvalues are negative;
`wcmdscale()` returns only the axes with positive eigenvalues, and the
percentages above are relative to their sum.

``` r

ggplot2::ggplot(scores_pcoa,
                ggplot2::aes(PCo1, PCo2, colour = site, shape = season)) +
  ggplot2::geom_point(size = 3, alpha = 0.8) +
  ggplot2::labs(
    x = sprintf("PCo1 (%.1f%%)", 100 * expl[1]),
    y = sprintf("PCo2 (%.1f%%)", 100 * expl[2]),
    colour = "Site", shape = "Season"
  ) +
  ggplot2::theme_bw()
```

Samples with identical frequencies share a single point. Non-metric
multidimensional scaling (NMDS) on the same dissimilarity, with stress
reported:

``` r

set.seed(2026)
nmds <- vegan::metaMDS(d, k = 2, trymax = 50, trace = FALSE)
nmds$stress
```

``` r

scores_nmds <- data.frame(freq_ord[, c("site", "season")],
                          vegan::scores(nmds))
ggplot2::ggplot(scores_nmds,
                ggplot2::aes(NMDS1, NMDS2, colour = site, shape = season)) +
  ggplot2::geom_point(size = 3, alpha = 0.8) +
  ggplot2::labs(colour = "Site", shape = "Season",
                caption = sprintf("Stress = %.3f", nmds$stress)) +
  ggplot2::theme_bw()
```

The low stress is expected: 2 species define a low-dimensional
configuration, and a two-dimensional NMDS reproduces it almost exactly.

### A note on inference

A PERMANOVA (`vegan::adonis2()`) could test for differences between
seasons, but the example does not support that test. There are only a
few samples from 4 sites, and months within a site are not independent
replicates: they share the site, its species pool and its recorder, and
consecutive months are temporally autocorrelated. Restricting
permutations to within sites (`strata = site`) respects the blocking by
site but not the temporal dependence, and the cell dropped for low
effort leaves the blocks unbalanced. The code is shown for completeness
and its p-value should not be interpreted:

``` r

set.seed(2026)
vegan::adonis2(d ~ season, data = freq_ord, strata = freq_ord$site,
               permutations = 999)
```

A design that supports inference would need more sites per treatment, or
a model that accounts explicitly for repeated measures within sites.
