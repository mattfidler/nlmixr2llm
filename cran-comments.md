## Submission

This is a new submission.

## Test environments

* local: macOS, R 4.5.1
* (add before submitting) win-builder (devel and release)
* (add before submitting) R-hub / macOS builder

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  Maintainer: 'John Harrold <john.m.harrold@gmail.com>'
  New submission.

## Notes for the maintainer

* The package installs LLM-facing documentation into external coding-agent
  locations. The `install_claude_code()` and `install_codex()` `scope = "user"`
  paths write under the user's home directory (`~/.claude`, `~/.codex`); these
  ask for confirmation in interactive sessions before writing, and all examples
  are wrapped in `\dontrun{}`, all tests redirect the base via
  `options(nlmixr2llm.home = tempdir())`, and all vignette installer chunks use
  `eval = FALSE`, so nothing is written outside `tempdir()` during R CMD check.
