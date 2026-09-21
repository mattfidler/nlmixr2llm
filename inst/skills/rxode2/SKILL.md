---
name: rxode2
description: Use this skill when the user is creating, editing, or running ODE-based pharmacometric models with the R package rxode2. Triggers include writing PK/PD models with `ini({}) / model({})` blocks, building event tables with `et()` / `eventTable()`, simulating with `rxSolve()`, population/clinical trial simulation, simulating with parameter uncertainty (`nStud`, `thetaMat`, `dfSub`, `prior()` lines in `ini({})`), adaptive dosing (`bolus()`, `infuse()`, `mtime()`, titration/TDM rules), piping changes onto a model or fit (`|> ini()`, `|> model()`), or debugging rxode2 compilation and solver errors.
---

# rxode2 — ODE-based PK/PD modeling in R

rxode2 translates an R-flavored ODE mini-language into compiled C for fast solving. A working rxode2 task always involves three pieces: a **model**, an **event table**, and a **solve call**.

## When to use this skill

Activate whenever the user is:

- Writing or editing a model that contains `ini({})`, `model({})`, `d/dt(...)`, or calls `rxode2()` / `rxSolve()` / `et()`.
- Asking for a PK, PD, or PK/PD simulation in R and rxode2 is a reasonable choice.
- Debugging an rxode2 compilation error, solver failure, or unexpected simulation output.
- Converting a NONMEM, Monolix, mrgsolve, or pkpdsim model into rxode2.

## Minimum viable example

Use this template as the starting point for any new model. Replace parameters, compartments, and event table to fit the user's problem.

```r
library(rxode2)

mod <- function() {
  ini({
    KA <- 0.294
    CL <- 18.6
    V  <- 40.2
  })
  model({
    C  <- central / V
    d/dt(depot) <- -KA * depot
    d/dt(central) <-  KA * depot - (CL/V) * central
  })
}
mod <- mod()                              # instantiate the UI object

ev <- et(amountUnits = "mg", timeUnits = "hours") |>
  et(amt = 100, cmt = "depot") |>
  et(0:24)

sim <- rxSolve(mod, ev)
head(sim)
plot(sim, C)
```

Always run the example (or its adapted form) and confirm it compiles and solves before handing it back.

## Authoring rules

1. **Model structure.** Use the function-style UI: an R function returning `ini({}) / model({})`. Call the function once (`mod <- mod()`) to get the UI object that `rxSolve` accepts; `rxode2(mod)` does the same thing.

   **ODE → `linCmt()` conversion (`useLinCmt`).** rxode2 can replace a mass-balanced linear ODE system with the equivalent analytic `linCmt()` solution at solve time (`odeToLin()`; `linToOde()` is the inverse). It is faster, but `linCmt()` uses canonical compartment names (`depot`, `central`, `peripheral1`, `peripheral2`), so a `d/dt(centr)` model then returns a solved column called `central` while `mod$state` still says `centr`. It is meant to be **off by default** (`getOption("rxode2.useLinCmt", FALSE)`), but that currently applies only to classic `rxode2({})` models: function-style models convert unless you pass `useLinCmt = FALSE`, and ignore the option ([rxode2#1389](https://github.com/nlmixr2/rxode2/issues/1389)).
   - Pass `useLinCmt = FALSE` to keep the ODE form and your names, or `TRUE` to force the conversion.
   - Name the central compartment `central` (and peripherals `peripheral1`/`peripheral2`) so the names agree either way.
   - A model that isn't mass-balanced (e.g. an effect compartment with its own turnover) is not converted. Neither is a model whose event data doses a compartment the conversion would rename away; it silently falls back to the ODE path.
2. **Compartments come from `d/dt(name)`.** The compartment is named by what's inside `d/dt(...)`. Reference it elsewhere (events, initial conditions) by that exact name.
3. **Initial conditions** go inside `model({})` as `name(0) <- value`, *not* in `ini({})`.
4. **Algebraic definitions** (e.g. `C <- central/V`) must appear before the ODEs that use them.
5. **Parameters.** Fixed effects in `ini({})` use `<-`. Random effects (between-subject variability) use `~` with a variance, e.g. `eta.cl ~ 0.1`. Residual error similarly: `add.err <- 0.1` then in `model` use `cp ~ add(add.err)`.
6. **Dose by compartment name** in `et()` (`cmt = "depot"`) — clearer than NONMEM-style integer indices and rxode2 supports it natively.
7. **Override parameters at solve time** via `params = c(CL = 20)` rather than editing `ini({})` for one-off scenarios. To keep the change with the model, pipe it: `mod |> ini(CL = 20)` returns a modified copy.
8. **Population sims.** Use `nSub` / `nStud` on `rxSolve`, supply `omega=` / `sigma=` / `thetaMat=` for variability and uncertainty propagation (see *Simulating with parameter uncertainty*). Use `cores=` for parallelism. For per-subject parameters or covariates, pass a `params=` data.frame keyed by `id` alongside an `events=` event table — or merge them into a single table (required if you have time-varying covariates).
9. **Reproducibility.** Set both `set.seed(...)` *and* `rxode2::rxSetSeed(...)` — they cover R-level and rxode2 internal RNG respectively.
10. **Population CIs.** Summarize a multi-subject sim with `confint(sim, "C", level = 0.95) |> plot()` to get a median + ribbon plot. Name any solved variable; `"ipred"`/`"sim"` only exist when the model has a residual-error line. rxode2 warns below ~2500 replicates that the bands aren't trustworthy, so size `nSub`/`nStud` accordingly.
11. **Pipe; don't retype.** `mod |> model(...)` and `mod |> ini(...)` (on a model *or* an nlmixr2 fit) return a modified copy. Use them to add a covariate, change a value, or bolt on a dosing protocol while the original model stays exactly as it was.

## Event-table cheatsheet

```r
# Single dose
et() |> et(amt = 100, cmt = "depot") |> et(0:24)

# Multiple dosing (q12h x 10)
et() |> et(amt = 100, addl = 9, ii = 12, cmt = "depot") |> et(0:120)

# Steady state
et() |> et(amt = 100, ii = 12, ss = 1, cmt = "depot") |> et(0:24)

# Infusion (rate-based)
et() |> et(amt = 100, rate = 10, cmt = "central") |> et(0:24)

# Infusion (duration-based)
et() |> et(amt = 100, dur = 10, cmt = "central") |> et(0:24)

# Multi-endpoint: one sampling pass PER endpoint, each naming its endpoint in cmt.
# A plain grid errors with "'dvid'->'cmt' or 'cmt' on observation record ...".
et() |> et(amt = 100, cmt = "depot") |> et(0:24, cmt = "cp") |> et(0:24, cmt = "effect")

# Multi-subject
et() |> et(amt = 100, cmt = "depot") |> et(0:24) |> et(id = 1:50)

# Combine separately built event tables (e.g. different arms)
etRbind(evArmA, evArmB)

# Per-subject dosing (e.g. weight-based) — loop and append
ev <- et()
for (i in seq_len(nSub)) {
  ev <- ev |> et(id = i, amt = dose[i], time = 0, addl = 9, ii = 12)
}
ev <- ev |> add.sampling(time = 0:240)   # add.sampling() adds obs times to an existing ev
```

NONMEM-format data frames with `ID/TIME/EVID/AMT/CMT/DV` are also accepted directly by `rxSolve`.

## Priors in `ini({})`

Priors sit next to the parameter they describe (needs `lotri` >= 1.0.5; `lotri::lotriPriorDists()` lists every distribution):

```r
mod <- function() {
  ini({
    tka <- 0.45; tcl <- 1; tv <- 3.45
    add.sd <- 0.7
    eta.ka ~ 0.6
    eta.cl + eta.v ~ c(0.3, 0.01, 0.1)
    prior(tka) ~ dnorm(0.45, 0.1)          # normal prior on a theta: dnorm(mean, SD)
    tcl + tv ~ c(0.02, 0.001, 0.03)        # joint normal on thetas (a $THETAPV block)
    prior(eta.cl, eta.v) ~ invWishart(20)  # inverse Wishart, df per OMEGA block (NWPRI)
    prior(eta.ka) ~ invWishart(4)
  })
  model({
    ka <- exp(tka + eta.ka); cl <- exp(tcl + eta.cl); v <- exp(tv + eta.v)
    linCmt() ~ add(add.sd)
  })
}
rxUiPriors(mod())   # what priors the model carries
```

| Form | Means | Simulation role |
|---|---|---|
| `prior(tka) ~ dnorm(mean, sd)` | normal prior on a theta | row/column of the `thetaMat` |
| `tka ~ 0.01` (inside `ini({})` only) | shorthand: normal, variance 0.01, mean = estimate | same |
| `tcl + tv ~ c(var, cov, var)` (inside `ini({})` only) | joint normal on thetas (`multiNormal`). Same shape as an OMEGA block; the left-hand names decide: thetas make a prior, etas make an OMEGA block | block of the `thetaMat` |
| `prior(eta.cl, eta.v) ~ invWishart(df)` | inverse Wishart on a whole OMEGA block | that block's degrees of freedom |
| `om.eta.cl ~ 0.01` or `prior(om.eta.cl) ~ dnorm(0.3, 0.1)` | normal prior on the omega value (TNPRI) | omega drawn jointly with thetas |

- Pipe a prior on or replace one: `mod |> ini(prior(tka) ~ dnorm(0.45, 0.05))`. But `mod |> ini(tka ~ 0.01)` **changes the estimate**. The shorthand forms only work inside an `ini({})` block.
- An OMEGA block takes either degrees of freedom or normal priors on its values, never both.
- Other distributions (`dcauchy()`, `dbeta()`, ...) are valid for *estimation* (nlmixr2 / nlmixr2bayes) but cannot be simulated from. Simulate such a model with `usePrior = FALSE` or an explicit `thetaMat`.

## Simulating with parameter uncertainty

Uncertainty is simulated **per study**: `nStud` studies each draw one set of thetas, omega, and sigma, then simulate `nSub` subjects from it.

```r
ev <- et(amt = 300) |> et(0:24)
set.seed(42); rxSetSeed(42)

# 1. From the ini() priors: nothing else to pass
s1 <- rxSolve(mod, ev, nStud = 100, nSub = 50)

# 2. From explicit arguments (e.g. a covariance step from any software)
s2 <- rxSolve(mod, ev, nStud = 100, nSub = 50, usePrior = FALSE,
              thetaMat = covMat,      # your named theta covariance matrix -> thetas ~ MVN
              dfSub = 40,             # omega ~ inverse Wishart(dfSub), usually the number of subjects
              dfObs = 400)            # sigma ~ inverse Wishart(dfObs), usually the number of observations

# 3. From an nlmixr2 fit (any fitted model): thetaMat, dfSub and dfObs are filled in
s3 <- rxSolve(fit, ev, nStud = 100, nSub = 50)

s3$omegaList[[1]]                   # the omega drawn for study 1 (also $sigmaList)
confint(s1, "sim", level = 0.90) |> plot()   # any solved variable; "sim" is the simulated observation
```

| Argument | Effect |
|---|---|
| `nStud` | number of between-study draws; `1` means no uncertainty |
| `usePrior` | `NA` (default) uses `ini()` priors when present; `TRUE` requires them; `FALSE` ignores them |
| `thetaMat` | theta covariance; passed at the call site it overrides priors |
| `dfSub` / `dfObs` | inverse-Wishart df for omega / sigma. The nlmixr2 team recommends this route for omega and sigma rather than their standard errors |
| `omegaSeparation`, `sigmaSeparation` | `"auto"`/`"lkj"`/`"separation"` redraw the matrix from `dfSub`. `"tnpri"` draws omega/sigma entries **jointly** with the thetas from a full covariance whose columns name the omega entries (`om.eta.cl`/`cov.eta.cl.eta.v` in nlmixr2's `fit$cov`; `eta1`/`omega.2.1` in nonmem2rx's `$thetaMat`), keeping theta–omega correlations. Entries with zero variance in that matrix (e.g. fixed or absent off-diagonals) are not drawn this way. **Known issue** ([rxode2#1388](https://github.com/nlmixr2/rxode2/issues/1388)): when the model or call also has a `dfSub` (every nlmixr2 fit and nonmem2rx import does), the off-diagonals still come from the inverse-Wishart draw. Pass `dfSub = 0` for a pure tnpri draw |
| `simVariability = FALSE` | typical-value thetas, no uncertainty |
| `priorPdRetry` | retries for a drawn covariance that is not positive definite (default 10) |

- **A fit estimated with priors** (MAP or Bayesian) still carries them, but its estimates have moved off the prior means, so `rxSolve(fit, ..., nStud = )` errors. Pass `usePrior = FALSE` to simulate from `fit$cov` instead.
- **A prior mean must equal the current estimate**, because draws are added to it. On a fit, splice in the exact unrounded value: `v <- fit$theta[["tka"]]; eval(bquote(ini(fit, prior(tka) ~ dnorm(.(v), 0.1))))`.
- Chunked or file-backed solves (`chunkSize=`, `file=`) cannot use priors and error rather than dropping them.
- Nested/occasion models: each prior's df applies to the level that holds its block; a prior covering only part of a level is an error.

## Adaptive dosing — pipe the protocol onto the model

When the dose depends on the simulated trajectory (titration, dose holds and reductions, rescue, TDM), it cannot be written into `et()`. Put the rule in `model({})` and push the event while solving (rxode2 >= 5.1.7):

| Helper | evid | Pushes |
|---|---|---|
| `bolus(amt, cmt, ii, addl, ss)` | 1 | a bolus |
| `infuse(amt, rate, cmt, ...)` / `infuseDur(amt, dur, cmt, ...)` | 1 | fixed-rate / fixed-duration infusion |
| `reset()` / `replace(amt, cmt)` / `multiply(f, cmt)` | 3 / 5 / 6 | reset all states / set / scale a compartment |
| `phantom(amt, cmt)` | 7 | transit bookkeeping (`tad()`, `podo()`) without mass |
| `obs(dt1, dt2, ...)` | 0 | extra observation rows |
| `evid_(...)` | any | low-level interface |

**Pipe the protocol onto the existing model or fit** instead of rewriting the PK/PD. Then the model that was fit, qualified, or published stays exactly as it was:

```r
tdm <- fit |>                                 # an nlmixr2 fit or any rxode2 model
  model({
    rescueAmt <- rescue                       # the dose amount must be a plain symbol assigned in model()
    if (t > 0 && t %% 24 == 0 && cp < target) {
      bolus(rescueAmt, cmt = depot)
    }
  }, append = TRUE, auto = FALSE) |>          # append after the residual line; don't auto-classify new symbols
  ini(target <- 3, rescue <- 160)             # protocol-only parameters

all.equal(tdm$theta[names(fit$theta)], fit$theta)   # TRUE: estimates untouched

sim <- rxSolve(tdm, et(amt = 320, cmt = "depot") |> et(seq(0, 96, by = 1)),
               nSub = 100, maxExtra = 500)
```

For multi-rule protocols (dose levels, holds, reassessment), keep the protocol's memory in **sticky** variables. These are LHS variables that start `NA` for each subject and keep their last value between records:

```r
if (is.na(level)) {        # first record of each subject
  level   <- 1
  nextDue <- 21*24
}
if (t > 0 && t %% 168 == 0 && t >= nextDue) {
  if (anc >= 1.5) {
    infuseDur(doseMg, 1, central)
    nextDue <- t + 21*24
  } else {
    nextDue <- t + 7*24    # hold a week and reassess
  }
}
```

Rules that bite:

- **Decisions only run at times the solver visits.** Put assessment times in the event table, or pin them with `mtime(check48) <- 48`. `mtime(48)` does not parse.
- **Anchor standing conditions.** `cp < target` is true for many rows, so tie it to a visit (`t %% 24 == 0`) and skip `t == 0`, or it fires every row.
- **Dose amounts must be symbols**: `doseMg <- mgm2*bsa`, then `infuseDur(doseMg, ...)`.
- **Set `maxExtra`** so a runaway rule errors instead of pushing thousands of events. An event pushed at the last output time never happens, but sticky assignments on that row still do.
- The event table can hold only observations when the model pushes every dose (including the first at `t == 0`).
- `linCmt()` models work too, and `odeToLin()` converts a linear ODE model while keeping its adaptive calls.
- Compare protocols by piping different rules onto the same base model, or vary a rule's thresholds with `params = c(target = 2)`.

## Running the model

The skill is "done" only when the model has been **executed and inspected**, not just written. Workflow:

1. Write the model + events + solve call to a file (or run via `Rscript -e '...'`).
2. Run it. Capture errors verbatim.
3. If it compiles, print `head(sim)` and a quick sanity check (max concentration, AUC, steady state behavior — whatever is physically meaningful for the user's problem).
4. Only then report results to the user.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `compartment 'X' not found` | `cmt=` in event table doesn't match a `d/dt(X)`. This surfaces at **solve** time; a misspelled compartment compiles fine |
| Output has `central` but the model says `centr` | the ODE → `linCmt()` conversion ran (see rule 1); pass `useLinCmt = FALSE` or name the compartment `central` |
| `parameter 'X' not found` | Symbol in `model({})` not in `ini({})`, not a compartment, not in `params=`, not a covariate column |
| Compilation fails | Syntax error in `model({})`; surface the rxode2 error message |
| `non-finite values` / max steps | Division by zero (zero volume?), discontinuous input, or stiff system — try `method = "lsoda"` explicitly |
| Output looks flat / zero | Forgot to instantiate (`mod()` vs `mod`), or dosing into the wrong compartment |
| Wrong magnitude | Unit mismatch between `timeUnits` in `et()` and rate constants in `ini` (h vs day) |

## What NOT to do

- Don't invent rxode2 syntax. If unsure, check `inst/syntax-functions.csv` or the vignettes under `vignettes/` in the rxode2 source repo (github.com/nlmixr2/rxode2).
- Don't hand the user pseudocode. Always produce a complete, runnable script with `library(rxode2)`.
- Don't skip the run step. A model that "looks right" but never compiled is not delivered.
- Don't overwrite the user's existing model parameters silently — if you change `ini({})` values, call it out.

## References (in the rxode2 source repo, github.com/nlmixr2/rxode2)

- `vignettes/rxode2-intro.Rmd` — canonical intro example
- `vignettes/rxode2-syntax.Rmd` — model language reference
- `vignettes/articles/rxode2-ui-object.Rmd` — function-style UI deep dive
- `vignettes/rxode2-event-table.Rmd`, `rxode2-event-types.Rmd`, `rxode2-events-classic.Rmd` — event specification
- `vignettes/rxode2-single-subject.Rmd` — single-subject simulation patterns
- `vignettes/rxode2-sim-var.Rmd` — population simulation with BSV / IIV
- `vignettes/articles/rxode2-clinical-trial-sim.Rmd` — clinical trial simulation patterns
- `vignettes/articles/rxode2-eta-eps-resampling.Rmd` — resampling fitted ETAs/EPSs (the pattern used above)
- `vignettes/articles/rxode2-parameter-uncertainty.Rmd` — propagating parameter uncertainty
- `vignettes/articles/adaptive-dosing.Rmd` — every in-model dosing helper, `mtime()`, `obs()`, `evid_()`
- `vignettes/articles/rxode2-sticky.Rmd` — sticky variables (protocol memory, running Cmax/Tmax)
- `vignettes/articles/rxode2-vpc.Rmd` — visual predictive checks
- `vignettes/rxode2-covariates.Rmd`, `rxode2-prior-data.Rmd` — covariates and external data
- `vignettes/articles/Modifying-Models.Rmd` — model piping / edits
- `inst/syntax-functions.csv`, `inst/reserved-keywords.csv` — language reference (in `inst/`, not vignettes)
