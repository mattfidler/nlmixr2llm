---
name: rxode2
description: Use this skill when the user is creating, editing, or running ODE-based pharmacometric models with the R package rxode2. Triggers include writing PK/PD models with `ini({}) / model({})` blocks, building event tables with `et()` / `eventTable()`, simulating with `rxSolve()`, population/clinical trial simulation, or debugging rxode2 compilation and solver errors.
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
    d/dt(depot)   <- -KA * depot
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

1. **Model structure.** Use the function-style UI: an R function returning `ini({}) / model({})`. Call the function once (`mod <- mod()`) to get the UI object that `rxSolve` accepts — `rxode2(mod)` does the same thing.
2. **Compartments come from `d/dt(name)`.** The compartment is named by what's inside `d/dt(...)`. Reference it elsewhere (events, initial conditions) by that exact name.

   At solve time rxode2 may replace a mass-balanced linear ODE system with the equivalent analytic `linCmt()` solved form (`odeToLin()`; `linToOde()` is the inverse). This is a speed optimization — the analytic solution beats numeric integration — and it is why a `depot` + `centr` model logs `renaming compartments` and returns a solved column called `central`: `linCmt()` uses the canonical names `depot` / `central` / `peripheral1` / `peripheral2`. `mod$state` still reports `centr` because the UI keeps the ODE form; the two are different views, not a disagreement. **Spell the central compartment `central` and they agree.** A model that isn't mass-balanced (e.g. an effect compartment with its own turnover) isn't converted and keeps your names.

   The conversion is skipped when the event data doses a compartment whose name it would rename away, so `cmt = "centr"` still solves — you just silently fall back to the slower ODE path. Naming compartments the `linCmt()` way is how you keep the speedup.
3. **Initial conditions** go inside `model({})` as `name(0) <- value`, *not* in `ini({})`.
4. **Algebraic definitions** (e.g. `C <- central/V`) must appear before the ODEs that use them.
5. **Parameters.** Fixed effects in `ini({})` use `<-`. Random effects (between-subject variability) use `~` with a variance, e.g. `eta.cl ~ 0.1`. Residual error similarly: `add.err <- 0.1` then in `model` use `cp ~ add(add.err)`.
6. **Dose by compartment name** in `et()` (`cmt = "depot"`) — clearer than NONMEM-style integer indices and rxode2 supports it natively.
7. **Override parameters at solve time** via `params = c(CL = 20)` rather than editing `ini({})` for one-off scenarios.
8. **Population sims.** Use `nSub` / `nStud` on `rxSolve`, supply `omega=` / `sigma=` / `thetaMat=` for variability and uncertainty propagation. Use `cores=` for parallelism.

   Two patterns for per-subject parameters/covariates — **A. re-draw from `omega`** (`rxSolve(mod, ev, nSub = 100)`), or **B. supply a per-subject table** when you have specific parameter sets per ID (e.g. post-hoc ETAs from a `nonmem2rx` conversion):

   ```r
   # sub_df has columns: id, CL, V, ... and any non-time-varying covariates (BW, etc.)
   sim <- rxSolve(mod, params = sub_df, events = ev)          # split tables
   # or merge into one table -- REQUIRED for time-varying covariates:
   evall <- as.data.frame(ev) |> dplyr::left_join(sub_df, by = "id")
   sim   <- rxSolve(mod, events = evall)
   ```
9. **Reproducibility.** Set both `set.seed(...)` *and* `rxode2::rxSetSeed(...)` — they cover R-level and rxode2 internal RNG respectively.
10. **Population CIs.** Summarize a multi-subject sim with `confint(sim, "C", level = 0.95) |> plot()` — name any solved variable (`"ipred"` only exists if the model has a residual-error block). rxode2 warns below ~2500 replicates that the bands aren't trustworthy, so size `nSub`/`nStud` accordingly.

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

# Multi-subject
et() |> et(amt = 100, cmt = "depot") |> et(0:24) |> et(id = 1:50)

# Multi-endpoint: one sampling pass PER endpoint, each naming its endpoint in cmt.
# A plain grid errors with "'dvid'->'cmt' or 'cmt' on observation record ...".
et() |> et(amt = 100, cmt = "depot") |> et(0:24, cmt = "cp") |> et(0:24, cmt = "effect")

# Per-subject dosing (e.g. weight-based) — loop and append
ev <- et()
for (i in seq_len(nSub)) {
  ev <- ev |> et(id = i, amt = dose[i], time = 0, addl = 9, ii = 12)
}
ev <- ev |> add.sampling(time = 0:240)   # add.sampling() adds obs times to an existing ev
```

NONMEM-format data frames with `ID/TIME/EVID/AMT/CMT/DV` are also accepted directly by `rxSolve`.

## Running the model

The skill is "done" only when the model has been **executed and inspected**, not just written. Workflow:

1. Write the model + events + solve call to a file (or run via `Rscript -e '...'`).
2. Run it. Capture errors verbatim.
3. If it compiles, print `head(sim)` and a quick sanity check (max concentration, AUC, steady state behavior — whatever is physically meaningful for the user's problem).
4. Only then report results to the user.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `compartment 'X' not found` | `cmt=` in event table doesn't match a `d/dt(X)`. Note this surfaces at **solve** time, not compile time — a misspelled compartment compiles fine |
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
- `vignettes/articles/rxode2-vpc.Rmd` — visual predictive checks
- `vignettes/rxode2-covariates.Rmd`, `rxode2-prior-data.Rmd` — covariates and external data
- `vignettes/articles/Modifying-Models.Rmd` — model piping / edits
- `inst/syntax-functions.csv`, `inst/reserved-keywords.csv` — language reference (in `inst/`, not vignettes)
