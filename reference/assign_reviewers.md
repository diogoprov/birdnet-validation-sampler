# Assign the clips to several reviewers

Splits the clips of a manifest among reviewers, balanced within each
species, and gives a fraction of them to a second reviewer, so that the
agreement between reviewers can be measured with
[`reviewer_agreement()`](https://provetelab.org/sheepdog/reference/reviewer_agreement.md).
The overlap is drawn within each species, so every species gets doubly
reviewed clips.

## Usage

``` r
assign_reviewers(manifest, reviewers, overlap = 0.1, seed = 2026)
```

## Arguments

- manifest:

  Clip manifest, as returned by
  [`select_clips()`](https://provetelab.org/sheepdog/reference/select_clips.md)
  or
  [`cut_clips()`](https://provetelab.org/sheepdog/reference/cut_clips.md).

- reviewers:

  Names of the reviewers (at least two).

- overlap:

  Fraction of the clips of each species reviewed by two reviewers.

- seed:

  Seed of the draws. The global random number generator is left as it
  was.

## Value

The manifest with `reviewer` (the first reviewer of each clip) and
`second_reviewer` (`NA` for clips reviewed once).

## Details

Cut the clips with
[`cut_clips()`](https://provetelab.org/sheepdog/reference/cut_clips.md)
first, then copy each reviewer's share to their own folder with
[`split_by_reviewer()`](https://provetelab.org/sheepdog/reference/split_by_reviewer.md).
