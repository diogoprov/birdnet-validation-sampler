# Read BirdNET selection tables

Finds every BirdNET selection table (Raven format, tab-separated) under
`data_dir`, reads them and stacks them in one table. Each table holds
the predictions of one site, and the site is the name of the folder that
contains it. The `output_` prefix of BirdNET output folders is removed,
so `output_UEM/` becomes site `UEM`.

## Usage

``` r
read_selection_tables(
  data_dir,
  table_pattern = "^BirdNET_SelectionTable\\.txt$"
)
```

## Arguments

- data_dir:

  Root folder, searched recursively.

- table_pattern:

  Regular expression for the table file names.

## Value

A tibble with one row per prediction, the column `site` first, followed
by the standardised table columns. The columns `begin_time`, `end_time`,
`species_code`, `confidence`, `begin_path` and `file_offset` are
required.

## Details

Column names are standardised to lower case without units or
punctuation, e.g. `Begin Time (s)` becomes `begin_time` and
`File Offset (s)` becomes `file_offset`.
