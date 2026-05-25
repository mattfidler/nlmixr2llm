---
name: monolix2rx
description: Use this skill when the user wants to convert a Monolix project (`.mlxtran` + results folder) into an rxode2 / nlmixr2 model object for simulation, sharing, or qualification. Triggers include calls to `monolix2rx()` or `mlxtran()`, references to `.mlxtran` files, "translate this Monolix project", or babelmixr2's Monolix back-translation step.
---

# monolix2rx — Monolix → rxode2 conversion

`monolix2rx` parses a Monolix `.mlxtran` project plus its results folder and produces an rxode2-based model object containing the structural model, fixed and random effects, and the information needed to qualify the translation against Monolix's own predictions.

## When to use this skill

Activate whenever the user is:

- Converting a finished Monolix run to rxode2 for simulation, VPC, or sharing.
- Pulling THETA / OMEGA / IIV out of a Monolix project into R.
- Reading Monolix output back into nlmixr2 (often via `babelmixr2`).
- Parsing an `.mlxtran` file structurally without running a full conversion (`mlxtran()`).

## Minimum viable example

```r
library(monolix2rx)

pkgTheo     <- system.file("theo", package = "monolix2rx")
mlxtranFile <- file.path(pkgTheo, "theophylline_project.mlxtran")

mod <- monolix2rx(mlxtranFile)
mod                # rxode2-based model with Monolix estimates baked in
```

For just structural parsing (no conversion to rxode2):

```r
proj <- mlxtran(mlxtranFile)
str(as.list(proj))
```

The returned `mod` is an rxode2-flavored model — solve it with `rxSolve(mod, ev)` like any other rxode2 model.

## Authoring rules

1. **Inputs.** `monolix2rx()` needs the `.mlxtran` file *and* the results folder Monolix produced next to it (typically a sibling directory). If results are missing, you only get the structural model — no estimates, no qualification.
2. **Required result artifacts** (typical Monolix output):
   - `summary.txt` — run info, observation/dose counts, Monolix version
   - `FisherInformation/covarianceEstimatesLin.txt` — covariance of fixed effects
   - the dataset referenced inside the `.mlxtran`
3. **Returned object is an rxode2 model**, with `$theta`, `$omega`, compartments, μ-referencing table, and a normalized R-function model body. It is *not* an nlmixr2 fit object on its own.
4. **Library models need configuration.** Monolix's binary model library (e.g. `lib:bolus_1cpt_TlagVCl.txt`) cannot be resolved by `monolix2rx` alone. Provide one of:
   - `options(monolix2rx.library = "/path/to/library")` pointing at a text-file mirror of the library, or
   - install `lixoftConnectors` (Monolix's R bridge) so the library can be looked up live, or
   - export the model to text in Monolix and re-point the `.mlxtran` at the text file.
5. **Qualification first.** Like `nonmem2rx`, the translation must be checked against Monolix's own predictions before downstream use. Use the qualification helpers from the `rxode2-validate` article.
6. **Simulating new dosing.** Build a fresh `et()` and call `rxSolve(mod, ev)`. For uncertainty propagation, pull the covariance via the parsed object.

## Workflow

The skill is "done" only when the converted model has been **executed and qualified**, not just loaded:

1. Run `monolix2rx()` and confirm the object prints without warnings.
2. Compare rxode2 IPRED/PRED against Monolix's own (qualification step from the `rxode2-validate` vignette workflow). Diffs should be effectively zero.
3. *Then* run the user's actual downstream task — new-dose sim, VPC, augPred, reporting.
4. Report qualification status alongside results.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `cannot find results folder` | `.mlxtran` was passed but the sibling results directory is missing or in a non-standard location |
| Library reference fails (`lib:...txt` not found) | Monolix library not configured — set `options(monolix2rx.library=...)` or install `lixoftConnectors` |
| `summary.txt` / `covarianceEstimatesLin.txt` not found | run was incomplete or covariance step skipped — re-run Monolix with the SE step enabled |
| Parameters present but `$omega` empty | random-effects parsing hit a feature monolix2rx doesn't translate — check the model body |
| IPRED disagrees with Monolix | unsupported Mlxtran feature (custom distributions, complex transforms, IOV with non-standard structure); inspect the generated rxode2 model and patch by hand |
| BLQ rows missing or wrong | BLQ handling differs between tools; verify the dataset's CENS/LIMIT columns survived translation |

## What NOT to do

- Don't trust the converted model without checking against Monolix's own PRED/IPRED.
- Don't pass only the `.mlxtran` and ignore the results folder if the user wanted estimates — the call will succeed but you'll miss `$theta` / `$omega` populated values.
- Don't try to handle Monolix library models without configuring one of the resolution paths above.
- Don't treat the result as an nlmixr2 fit — it's an rxode2 model.

## In-repo references

- `vignettes/articles/convert-nlmixr2.Rmd` — promoting to nlmixr2 fit-like
- `vignettes/articles/rxode2-validate.Rmd` — qualification against Monolix
- `vignettes/articles/simulate-new-dosing.Rmd`, `simulate-uncertainty.Rmd`, `simulate-extra-items.Rmd` — downstream simulation patterns
- `vignettes/articles/create-vpc.Rmd`, `create-augPred.Rmd`, `create-office.Rmd` — reporting

## Relationship to babelmixr2

`babelmixr2`'s Monolix backend uses `monolix2rx` to read Monolix results back into R after a fit. If a babelmixr2 Monolix fit looks wrong, reproduce the failure by loading the same `.mlxtran` directly with `monolix2rx()` — that isolates a translation bug from a babelmixr2 wiring bug.
