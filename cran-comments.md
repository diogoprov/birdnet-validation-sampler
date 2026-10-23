## Submission candidate

Prepared for an initial CRAN submission of sheepdog 3.2.1.
This file does not imply that a submission has already been uploaded.

## Test environment

- Local macOS, aarch64-apple-darwin23, R 4.6.1.
- R CMD check --as-cran, with all package vignettes built and rebuilt,
  and both PDF and HTML manuals checked using HTML Tidy 5.8.0.

## R CMD check results

0 errors | 0 warnings | 0 notes

Fast tests: 416 passed; one optional Stan integration test skipped.
That integration test was also run separately and passed 23 checks.

GitHub Actions release-R checks on Linux, Windows and macOS passed for
an earlier release; checks for this exact candidate on R-devel and the
other platforms should be confirmed before upload. A Linux R-devel job
has been added to the check workflow.

## Optional repositories

crywolf is an optional Suggests dependency outside CRAN. Its repository
and the repository supplying cmdstanr are declared in Additional_repositories:
https://diogoprov.r-universe.dev and https://stan-dev.r-universe.dev.
Tests using optional dependencies are conditional. Stan fitting is opt-in
and is not run by normal CRAN checks.

## Size and benchmark material

The checked source archive is approximately 3.8 MB. The acoustic example
is simulated and contains no audio files. Cached performance tables are
small derived summaries; benchmark fitting and downloads are opt-in
scripts excluded from the source tarball. Vignette builds use the cached
tables and never download the original benchmark data or refit Stan.
Attribution and the source-data licence are recorded in
inst/benchmarks/README.md and the performance vignette.
