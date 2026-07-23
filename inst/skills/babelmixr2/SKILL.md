---
name: babelmixr2
description: Use this skill when the user wants to fit an nlmixr2-style model using a non-nlmixr2 backend — NONMEM, Monolix, or PKNCA — through `babelmixr2`. Triggers include `nlmixr(..., est = "nonmem")`, `est = "monolix"`, `est = "pknca"`, calls to `nonmemControl()` / `monolixControl()` / `pkncaControl()`, or "run my nlmixr2 model in NONMEM/Monolix".
---

# babelmixr2 — run nlmixr2 models on other engines

`babelmixr2` translates an nlmixr2 model function into the input format of another tool (NONMEM, Monolix, PKNCA, and several R packages), runs that tool, reads its output files back onto the model it already has, and hands you what looks like a normal `nlmixr2` fit object. The user writes one model in nlmixr2 syntax and can fit it across engines for cross-validation, regulatory submission, or NCA.

## When to use this skill

Activate whenever the user is:

- Writing `nlmixr(model, data, est = "nonmem" | "monolix" | "pknca", ...)`.
- Authoring `nonmemControl()`, `monolixControl()`, or `pkncaControl()`.
- Configuring `options("babelmixr2.nonmem")` / `options("babelmixr2.monolix")`.
- Comparing the same nlmixr2 model across engines, or reading NONMEM/Monolix output back into R.

## Supported backends

| `est=` | What babelmixr2 does |
|---|---|
| `"nonmem"` | Generates a control stream + dataset, runs NONMEM via `runCommand`, reads results back and combines with the original model to return an nlmixr2 fit object |
| `"monolix"` | Generates an `.mlxtran` project + dataset, runs Monolix (CLI or `lixoftConnectors`), reads results back and combines the original model to return an nlmixr2 fit object |
| `"pknca"` | Runs non-compartmental analysis via `PKNCA` on the dataset and wraps the result in an nlmixr2-shaped object — useful as a starting point for popPK initial estimates |

babelmixr2 registers several further backends that route the same model function to other R packages. They are less commonly used but are real `est=` values:

| `est=` | Backend | Control |
|---|---|---|
| `"poped"` | Optimal design via `PopED` | see the PopED article |
| `"saemix"` | SAEM via the `saemix` package | `saemixControl()` |
| `"nlmer"` | `lme4::nlmer` | `nlmerControl()` |
| `"fmeMcmc"` | MCMC via `FME::modMCMC` | `fmeMcmcControl()` |
| `"pseudoOptim"` | Pseudo-random optimization | — |

## Minimum viable example — NONMEM

```r
library(babelmixr2)
options("babelmixr2.nonmem" = "nmfe743")    # set once per R session

pk.turnover.emax3 <- function() {
  ini({
    tktr <- log(1);  tka <- log(1)
    tcl  <- log(0.1); tv  <- log(10)
    eta.ktr ~ 1; eta.ka ~ 1; eta.cl ~ 2; eta.v ~ 1
    prop.err  <- 0.1
    pkadd.err <- 0.1
    temax <- logit(0.8); tec50 <- log(0.5)
    tkout <- log(0.05);  te0   <- log(100)
    eta.emax ~ .5; eta.ec50 ~ .5; eta.kout ~ .5; eta.e0 ~ .5
    pdadd.err <- 10
  })
  model({
    ktr <- exp(tktr + eta.ktr)
    ka  <- exp(tka  + eta.ka)
    cl  <- exp(tcl  + eta.cl)
    v   <- exp(tv   + eta.v)
    emax <- expit(temax + eta.emax)
    ec50 <- exp(tec50 + eta.ec50)
    kout <- exp(tkout + eta.kout)
    e0   <- exp(te0   + eta.e0)
    DCP <- center / v
    PD  <- 1 - emax * DCP / (ec50 + DCP)
    effect(0) <- e0
    kin <- e0 * kout
    d/dt(depot)  <- -ktr * depot
    d/dt(gut)    <-  ktr * depot - ka * gut
    d/dt(center) <-  ka  * gut   - cl / v * center
    d/dt(effect) <-  kin * PD    - kout * effect
    cp <- center / v
    cp     ~ prop(prop.err) + add(pkadd.err)
    effect ~ add(pdadd.err) | pca
  })
}

fit <- nlmixr(pk.turnover.emax3, nlmixr2data::warfarin, "nonmem",
              nonmemControl(modelName = "pk.turnover.emax3"))
```

## Minimum viable example — Monolix

Same model function, swap the last call:

```r
options("babelmixr2.monolix" = "monolix")    # or rely on lixoftConnectors

fit <- nlmixr(pk.turnover.emax3, nlmixr2data::warfarin, "monolix",
              monolixControl(modelName = "pk.turnover.emax3"))
```

## Authoring rules

1. **One model, many engines.** Write the model exactly once in the nlmixr2 function-style UI (`ini({}) / model({})`). The same function works across `est=` values — don't fork it per engine.
2. **`modelName`** controls the output directory name. Set it explicitly so re-runs are reproducible and don't overwrite each other.
3. **Tell babelmixr2 where the engine lives.** Configure once per session:
   - NONMEM: `options("babelmixr2.nonmem" = "nmfe743")` (or full path), or pass `runCommand=` to `nonmemControl()`.
   - Monolix: install `lixoftConnectors` and it auto-detects, or set `options("babelmixr2.monolix" = "monolix")`, or pass `runCommand=` to `monolixControl()`.
4. **`runCommand` can be a function.** Signature is `function(ctl, directory, ui)`. Useful for cluster submission — return after the run completes and the output files exist. Setting it to `NA` makes `nlmixr()` stop after writing the engine input without running anything.
5. **The result is an nlmixr2 fit.** Standard post-processing works: `fit$parFixed`, `augPred(fit)`, `vpcPlot(fit)`, `fit$omega`, `as.data.frame(fit)`. If something appears missing, it usually means the import hit an unsupported output — see Debugging below.
6. **PKNCA is the odd one out.** `est = "pknca"` doesn't fit a model — it runs NCA and returns an object you can use to seed initial estimates for a subsequent popPK fit. Drive it with `pkncaControl(concu=, doseu=, timeu=, volumeu=)`.
7. **Other `nonmemControl()` arguments worth knowing.** `readRounding` defaults to `FALSE`; set `TRUE` to read partial results after a rounding-error finish. `sigdig`, `sigl`, and `tol` mirror the corresponding NONMEM `$EST` convergence options.

## Workflow

The skill is "done" only when the fit has been **executed and inspected**, not just queued:

1. Confirm the engine path is set (`getOption("babelmixr2.nonmem")` etc.).
2. Run `nlmixr(...)` with the chosen `est=`. Capture stdout/stderr — engine errors surface here.
3. After the run, inspect: `print(fit)`, `fit$parFixed`, an `augPred()` plot or VPC. Verify the OFV / objective is finite and parameters are sane.
4. *Then* report results.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `could not find NONMEM` / `could not find Monolix` | `runCommand` not set or wrong; check `getOption("babelmixr2.nonmem")` |
| Run launches but exits with rounding errors | model didn't converge — same fix as in NONMEM directly; consider `nonmemControl(readRounding = TRUE)` to read partial results |
| Fit object missing standard errors / `$parFixed` empty | reading the engine's output files failed silently — load the engine output independently with `nonmem2rx()` / `monolix2rx()` and inspect |
| Parameter estimates differ from a hand-written ctl | babelmixr2 generates `MU`-referenced code and manual ctls often don't — check the `MU` references, the `$THETA` bounds, and the dataset column ordering |
| Monolix run "succeeds" but no fit | `lixoftConnectors` not installed *and* `babelmixr2.monolix` option unset |
| PKNCA result has no concentrations | unit args (`concu`, `doseu`, `timeu`, `volumeu`) missing or inconsistent with the dataset |

## What NOT to do

- Don't rewrite the model in NONMEM control-stream syntax by hand. The whole point of babelmixr2 is to *not* do that.
- Don't trust a fit you haven't inspected. Engine runs can "succeed" and still produce a degenerate fit object if reading the results broke.
- Don't mix `est=` between runs without changing `modelName` — output directories will collide.
- Don't ignore `nonmem2rx` / `monolix2rx` errors raised while reading engine output; they're the canary for unsupported features.

## References (in the babelmixr2 source repo, github.com/nlmixr2/babelmixr2)

- `vignettes/articles/running-nonmem.Rmd` — full NONMEM workflow
- `vignettes/articles/running-monlix.Rmd` — full Monolix workflow
- `vignettes/articles/running-pknca.Rmd` — NCA → popPK initial estimates
- `vignettes/articles/new-estimation.Rmd` — adding a new backend
- `vignettes/articles/PopED.Rmd` — optimal design integration

## Relationship to nonmem2rx and monolix2rx

`babelmixr2` is the *forward* path (nlmixr2 → engine). `nonmem2rx` and `monolix2rx` are the *backward* path (engine output → rxode2/nlmixr2).

babelmixr2 does **not** call the backward *model* translation after a run completes, because it already knows what the original nlmixr2 model was. What it does use are those packages' low-level output readers — `nonmem2rx::nminfo()`, `nmext()`, `nmtab()`, `nmcov()`, `nmxml()` and the Monolix equivalents — to pull estimates, covariance, and tables off disk and attach them to the model it already has.

So if a babelmixr2 fit looks broken, suspect result reading or engine convergence rather than model translation. Debug by loading the engine output directly with `nonmem2rx()` / `monolix2rx()` and calling `babelmixr2::as.nlmixr2()` on the result: that is an independent path to the same run, so a clean result there points at babelmixr2's reader, and a bad result there points at the engine output.
