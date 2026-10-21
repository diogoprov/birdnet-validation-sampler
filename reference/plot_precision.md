# Plot the precision curves

One panel per species: precision by confidence bin, with the target
precision as a dashed line and bins with low support shown faded. Needs
the 'ggplot2' package.

## Usage

``` r
plot_precision(
  precision,
  bins = seq(0.1, 1, by = 0.1),
  target_precision = 0.9,
  min_n = 15
)
```

## Arguments

- precision:

  Table returned by
  [`precision_by_bin()`](https://provetelab.org/birdnet-validation-sampler/reference/precision_by_bin.md).

- bins:

  Breaks of the confidence bins (left-closed).

- target_precision:

  Target precision.

- min_n:

  Minimum of reviewed clips for a bin to be taken seriously; bins with
  fewer are flagged in `low_support`.

## Value

A ggplot object.
