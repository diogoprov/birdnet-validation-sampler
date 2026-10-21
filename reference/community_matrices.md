# Community matrices from the detection history

Turns the calibrated nightly detection history into site x month
community matrices for multivariate ordinations (PCoA, NMDS, RDA).
Because those analyses do not model false positives, the entry rule is
strict:

- a species counts as detected on a night only when it had at least
  `k_min` reliable detections that night, i.e. detections with a
  calibrated probability \>= `p_min` of
  [`calibrate()`](https://provetelab.org/birdnet-validation-sampler/reference/calibrate.md)
  (column `detection_k<k_min>` of the history);

- only the core species enter the matrix: species whose calibration is
  reliable at every site. Other species would create artefactual beta
  diversity from differences in classifier recall among sites;

- each cell is the frequency of nights with detection, standardised by
  effort: nights with detection / nights recorded at that site x month.

## Usage

``` r
community_matrices(history, core_species, k_min = 2, min_nights_month = 5)
```

## Arguments

- history:

  Nightly detection history, as returned by
  [`detection_history()`](https://provetelab.org/birdnet-validation-sampler/reference/detection_history.md)
  (v1.2.0 `historico_deteccao_noite.csv` tables are also accepted).

- core_species:

  Species codes (the `species` column) that enter the matrix.

- k_min:

  Repetition rule: 1, 2 or 3 reliable detections on the night.

- min_nights_month:

  Site x month cells with fewer recorded nights are dropped from the
  matrices (unstable frequencies) and flagged in `effort`.

## Value

A list with three tibbles: `frequency` and `counts` (one row per site x
month, with `site`, `month`, `n_nights_recorded` and one column per core
species) and `effort` (`site`, `month`, `n_nights_recorded`,
`included`).

## Details

Effort (nights recorded) is approximated by the number of distinct
nights in the history of the site, for any species. With dense
detections, every night actually recorded appears in the history.
