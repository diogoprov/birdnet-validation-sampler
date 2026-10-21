# Build the validation clip set

Runs the whole first stage: reads the selection tables, selects the
clips, cuts them, writes `clip_manifest.csv` and zips one package per
species. This is the function form of the v1.2.0 script
`extrair_clipes_validacao.R`.

## Usage

``` r
extract_validation_clips(
  data_dir,
  output_dir,
  ...,
  table_pattern = "^BirdNET_SelectionTable\\.txt$",
  make_zip = TRUE,
  simulate = FALSE
)
```

## Arguments

- data_dir:

  Root folder, searched recursively.

- output_dir:

  Output folder; created if needed.

- ...:

  Sampling design, passed to
  [`select_clips()`](https://provetelab.org/sheepdog/reference/select_clips.md)
  (e.g. `sampling_mode`, `n_top`, `threshold`, `target_total`,
  `remap_from`, `remap_to`).

- table_pattern:

  Regular expression for the table file names.

- make_zip:

  Zip one package per species (skipped when `simulate` is `TRUE`).

- simulate:

  If `TRUE`, no audio is cut (the empty species folders are still
  created), but `status` tells what would be done. Useful to check a
  selection before cutting.

## Value

The manifest written to `clip_manifest.csv`, invisibly.

## Details

Output structure:

    <output_dir>/clips/<species_folder>/*.wav
    <output_dir>/packages/<species_folder>.zip
    <output_dir>/clip_manifest.csv

## Examples

``` r
if (FALSE) { # \dontrun{
# Check the selection first, then cut
extract_validation_clips("N:/Arara", "N:/Arara/validation",
                         remap_from = "N:/", remap_to = "/Volumes/Arara/",
                         simulate = TRUE)
} # }
```
