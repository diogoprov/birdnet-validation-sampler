# Select the clips to validate

Applies the sampling design to the predictions read by
[`read_selection_tables()`](https://provetelab.org/sheepdog/reference/read_selection_tables.md)
and returns the clip manifest: one row per clip to cut, with its site,
species, night, source audio, start and end. No audio is read or
written; cut the clips with
[`cut_clips()`](https://provetelab.org/sheepdog/reference/cut_clips.md).

## Usage

``` r
select_clips(
  detections,
  sampling_mode = c("top", "random_detections", "random_recordings"),
  occasion_unit = c("file", "minute"),
  threshold = NULL,
  n_top = 2,
  recording_fraction = 0.01,
  n_recordings_per_site = NULL,
  recordings = NULL,
  audio_pattern = "\\.(wav|flac|mp3)$",
  recording_duration = NULL,
  min_confidence = 0.1,
  sites = NULL,
  date_start = NULL,
  date_end = NULL,
  species = NULL,
  hour_start = NULL,
  hour_end = NULL,
  alternate_days = FALSE,
  target_total = NULL,
  balance_by_hour = TRUE,
  max_per_species = NULL,
  remap_from = NULL,
  remap_to = NULL,
  seed = 2026
)
```

## Arguments

- detections:

  Predictions, as returned by
  [`read_selection_tables()`](https://provetelab.org/sheepdog/reference/read_selection_tables.md).

- sampling_mode:

  `"top"`, `"random_detections"` or `"random_recordings"`. See *Sampling
  modes*.

- occasion_unit:

  The occasion of the occupancy model: `"file"` (the whole recording) or
  `"minute"` (minute of the file, from `file_offset`).

- threshold:

  Confidence threshold of the occupancy analysis. It defines the
  candidate occasions of `"random_detections"` and the
  `n_detections_occasion` column. `NULL` leaves that column `NA`.

- n_top:

  `"top"`: predictions kept per site x species x night x hour.
  `"random_detections"`: occasions drawn per site x species x night x
  hour.

- recording_fraction:

  `"random_recordings"`: fraction of the recordings (or minutes) drawn
  at each site.

- n_recordings_per_site:

  `"random_recordings"`: fixed number of recordings (or minutes) per
  site, used instead of `recording_fraction`.

- recordings:

  `"random_recordings"`: the list of all recordings, as a data frame or
  the path to a CSV file with the columns `site` and `source_audio` (the
  v1.2.0 columns `local` and `caminho_audio` are also read). `NULL`
  lists the files matching `audio_pattern` in the audio folders that
  appear in `begin_path`; folders without any prediction are then left
  out.

- audio_pattern:

  Regular expression for the audio files listed when `recordings` is
  `NULL`.

- recording_duration:

  Length of the recordings (s), for `occasion_unit = "minute"` in
  `"random_recordings"` and for the end of whole-recording clips. `NULL`
  reads each file with the 'av' package when needed (minute occasions)
  and leaves `clip_end` as `NA` otherwise.

- min_confidence:

  Minimum confidence of a candidate prediction in `"top"`. `NULL`
  applies no filter. The random modes use `threshold`.

- sites:

  Restrict to these sites. `NULL` keeps all.

- date_start, date_end:

  Date window of the recordings (`"YYYYMMDD"`). `NULL` leaves that side
  open.

- species:

  Restrict to these short species codes (the last part of
  `species_code`, e.g. `"boa-ran"`). `NULL` keeps all.

- hour_start, hour_end:

  Hour window (0-23). It can cross midnight:
  `hour_start = 17, hour_end = 2` keeps 17h-23h and 0h-2h, and the
  grouping becomes by night (small hours count as the night before).
  `NULL` applies no filter.

- alternate_days:

  Keep alternate days (or nights), anchored on the first date of each
  site.

- target_total:

  Total clips per site, split evenly among species by water filling:
  species with fewer clips than the quota enter whole and the surplus
  goes to the others. In `"random_detections"` it counts occasions.
  Ignored in `"random_recordings"`. `NULL` sets no target.

- balance_by_hour:

  Within each species, draw round-robin across the hours of the day
  (covers the diel cycle) when applying `target_total` or
  `max_per_species`.

- max_per_species:

  Simpler alternative to `target_total`: a fixed limit per site x
  species. Ignored when `target_total` is set.

- remap_from, remap_to:

  Replace the prefix `remap_from` of the `begin_path` paths by
  `remap_to`, e.g. `"N:/"` and `"/Volumes/Arara/"`. Backslashes are
  turned into forward slashes first.

- seed:

  Seed of every random draw. The global random number generator is left
  as it was.

## Value

A tibble, the clip manifest without `status`, with the columns `site`,
`species_code`, `species_folder`, `recording_date`, `night`,
`recording_hour`, `rank`, `confidence`, `clip_file`, `clip_start`,
`clip_end`, `duration`, `source_audio`, `begin_path`, `sampling_mode`,
`occasion_id`, `n_detections_occasion` and `inclusion_prob`. See
[`vignette("crywolf-integration")`](https://provetelab.org/sheepdog/articles/crywolf-integration.md)
for their definitions.

## Sampling modes

- `"top"` keeps the `n_top` predictions with the highest confidence per
  site x species x night x hour. It serves classifier retraining and the
  score-to-probability calibration of
  [`calibrate()`](https://provetelab.org/sheepdog/reference/calibrate.md).
  Do not use it to estimate false-positive rates: top-score clips hold
  fewer false positives than a random sample.

- `"random_detections"` draws, at random, `n_top` occasions per site x
  species x night x hour among the occasions with at least one
  prediction of the species with confidence \>= `threshold`, and keeps
  every prediction \>= `threshold` of each drawn occasion. This is the
  observation-confirmation design of Chambert et al. (2015,
  [doi:10.1890/14-1507.1](https://doi.org/10.1890/14-1507.1) ).

- `"random_recordings"` draws recordings (or minutes) among all those
  recorded, with or without predictions, in proportion to the effort of
  each site, for annotation by ear. This is the multiple-method design
  of Miller et al. (2011,
  [doi:10.1890/10-1396.1](https://doi.org/10.1890/10-1396.1) ). The clip
  is the whole recording (or minute), copied once per species to
  annotate, and `confidence` is `NA`.

In both random modes, use the same `threshold` as the occupancy
analysis.
