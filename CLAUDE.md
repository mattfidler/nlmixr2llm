Whenever changes or updates are made, remember to update documentation
(function examples, vignettes, etc).

After any documentation change (roxygen comments, vignettes, README, or the
agent/skill content), rebuild the generated docs so the rendered site stays in
sync:

- Regenerate man pages from roxygen: `Rscript -e 'roxygen2::roxygenise()'`
- Rebuild the pkgdown site: `Rscript -e 'pkgdown::build_site(preview = FALSE)'`
  (or, for a smaller diff, `pkgdown::build_article("<name>")` and/or
  `pkgdown::build_reference()` for just the changed pages).

## CRAN tests: never assert on timing

- Never put a wall-clock timing expectation in a test that can run on CRAN:
  no `expect_lt()`/`expect_true()` on `Sys.time()` differences,
  `system.time()`, `proc.time()`, `bench`/`microbenchmark` results, or any
  other elapsed-time threshold. CRAN check machines are shared and heavily
  loaded, so elapsed time there is random and a timing assertion fails at
  random. Example: nlmixr2plot `test-model-diagram.R` asserted a
  `modelGraph()` call took < 30 s; on CRAN it took 48.4 s and failed.
- Test the result, not the speed. If a speed regression guard is really
  needed, put it only in a test that starts with `skip_on_cran()` (or the
  package's own CRAN skip helper), and never in examples or vignettes.
- Tests that take more than a few seconds should also skip on CRAN.
