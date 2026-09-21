---
name: babelmixr2
description: Use this skill when the user wants to fit an nlmixr2-style model using a backend that babelmixr2 provides — NONMEM, Monolix, PKNCA, lme4::nlmer, saemix, FME (MCMC / pseudo-random global search) — or build a PopED optimal design from an nlmixr2 model. Triggers include `nlmixr(..., est = "nonmem")`, `est = "monolix" | "pknca" | "nlmer" | "saemix" | "fmeMcmc" | "pseudoOptim" | "poped"`, calls to `nonmemControl()` / `monolixControl()` / `pkncaControl()` / `nlmerControl()` / `saemixControl()` / `fmeMcmcControl()` / `pseudoOptimControl()` / `popedControl()`, or "run my nlmixr2 model in NONMEM/Monolix".
---

# babelmixr2 — run nlmixr2 models on other engines

`babelmixr2` translates an nlmixr2 model function into the input format of another tool (NONMEM, Monolix, PKNCA, and the R packages lme4, saemix, FME, and PopED), runs that tool, parses the results back, and hands you what looks like a normal `nlmixr2` fit object. The user writes one model in nlmixr2 syntax and can fit it across engines for cross-validation, regulatory submission, or NCA.

## When to use this skill

Activate whenever the user is:

- Writing `nlmixr(model, data, est = "nonmem" | "monolix" | "pknca" | "nlmer" | "saemix" | "fmeMcmc" | "pseudoOptim" | "poped", ...)`.
- Authoring the matching control (`nonmemControl()`, `monolixControl()`, `pkncaControl()`, `nlmerControl()`, `saemixControl()`, `fmeMcmcControl()`, `pseudoOptimControl()`, `popedControl()`).
- Setting up a PopED optimal-design evaluation or optimization from an nlmixr2 model.
- Configuring `options("babelmixr2.nonmem")` / `options("babelmixr2.monolix")`.
- Comparing the same nlmixr2 model across engines, or reading NONMEM/Monolix output back into R.

## Supported backends

| `est=` | What babelmixr2 does |
|---|---|
| `"nonmem"` | Generates a control stream + dataset, runs NONMEM via `runCommand`, reads results back and combines with the original model to return an nlmixr2 fit object |
| `"monolix"` | Generates an `.mlxtran` project + dataset, runs Monolix (CLI or `lixoftConnectors`), reads results back and combines the original model to return an nlmixr2 fit object |
| `"pknca"` | Runs non-compartmental analysis via `PKNCA` on the dataset and wraps the result in an nlmixr2-shaped object — useful as a starting point for popPK initial estimates |

In-R backends (no external software needed):

| `est=` | Model type | What babelmixr2 does |
|---|---|---|
| `"nlmer"` | mixed-effects | Fits with `lme4::nlmer` (Laplace), using analytic gradients from rxode2 sensitivities; mu-referenced or not. Raw fit in `fit$nlmer`; `nlmerControl(returnNlmer = TRUE)` returns it directly |
| `"saemix"` | mixed-effects | Fits with the `saemix` package's SAEM. Raw fit in `fit$saemix`. **Currently needs an ODE model with an eta on every structural theta**: `linCmt()` models and thetas without etas fail ([#212](https://github.com/nlmixr2/babelmixr2/issues/212)) |
| `"fmeMcmc"` | pooled (no etas) | MCMC with `FME::modMCMC()`; priors go in `fmeMcmcControl(prior = )`, not `ini()`. `coda::as.mcmc(fit)` gives the chain; set `seed=` for reproducibility |
| `"pseudoOptim"` | pooled (no etas) | Global pseudo-random search with `FME::pseudoOptim()`. **Every** parameter needs finite bounds in `ini()` (`tcl <- c(-5, 1, 5)`) |
| `"poped"` | mixed-effects | Not a fit: builds a PopED database from the model and a design event table for optimal design |

Methods that fit on the wrong model type error clearly ("needs to be a mixed effect model" / "can only have population estimates, try 'focei'"). None of the babelmixr2 methods accept `prior()` lines in `ini()`; the fit is refused rather than run without them.

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

## Optimal design with PopED

```r
library(babelmixr2)
library(PopED)

# design: doses + sampling times; low/high become PopED's minxt/maxxt windows
e <- et(amt = 1, ii = 24, until = 250) |>
  et(time = c(1, 2, 8, 240, 245)) |>
  as.data.frame() |>
  dplyr::mutate(low  = c(NA_real_, 0, 0, 0, 240, 240),
                high = c(NA_real_, 10, 10, 10, 248, 248))

db <- nlmixr(f, e, "poped",                   # f: a normal nlmixr2 model function
             popedControl(a    = list(c(DOSE = 20), c(DOSE = 40)),
                          maxa = c(DOSE = 200),
                          mina = c(DOSE = 0)))
evaluate_design(db)                           # FIM, expected RSE%
# poped_optim(db, opt_xt = TRUE)              # optimize sampling times
```

babelmixr2 generates PopED's model functions and parameter vectors from the model. In the design table, observation `time`s become `xt`, `low`/`high` become the sampling windows, an integer `dvid` becomes `model_switch`, `G_xt` is the grouping variable, and `id` identifies each design group. Design variables and covariates (`DOSE` above) go in `popedControl(a = )`. Ported PopED examples, including design priors (passed through `popedControl()`, not `ini()` `prior()` lines), IOV, covariate distributions, full covariance, and adaptive dosing, are in `system.file("poped", package = "babelmixr2")` (`ex.*.babelmixr2.R`).

## Authoring rules

1. **One model, many engines.** Write the model exactly once in the nlmixr2 function-style UI (`ini({}) / model({})`). The same function works across `est=` values — don't fork it per engine.
2. **`modelName`** controls the output directory name. Set it explicitly so re-runs are reproducible and don't overwrite each other.
3. **Tell babelmixr2 where the engine lives.** Configure once per session:
   - NONMEM: `options("babelmixr2.nonmem" = "nmfe743")` (or full path), or pass `runCommand=` to `nonmemControl()`.
   - Monolix: install `lixoftConnectors` and it auto-detects, or set `options("babelmixr2.monolix" = "monolix")`, or pass `runCommand=` to `monolixControl()`.
   - Key `nonmemControl()` arguments: `est` (`"focei"`, `"imp"`, `"its"`, `"posthoc"`), `cov` (`"r,s"`, `"r"`, `"s"`, `""`), `sigdig`/`sigl` (`$EST` precision), `maxeval`, `advanOde` (`"advan13"`, `"advan8"`, `"advan6"`) with `tol`/`atol` (ODE solver tolerances), and `readRounding` (`FALSE` by default; `TRUE` reads results after a rounding-error finish).
4. **`runCommand` can be a function.** Useful for cluster submission — return after the run completes and the output files exist.
5. **The result is an nlmixr2 fit.** Standard post-processing works: `fit$parFixed`, `augPred(fit)`, `vpcPlot(fit)`, `fit$omega`, `as.data.frame(fit)`. If something appears missing, it usually means the import hit an unsupported output — see Debugging below.
6. **PKNCA and PopED don't fit a model.** `est = "pknca"` runs NCA and returns an object you can use to seed initial estimates for a subsequent popPK fit; drive it with `pkncaControl(concu=, doseu=, timeu=, volumeu=)`. `est = "poped"` returns a PopED database for design evaluation and optimization.

## Workflow

The skill is "done" only when the fit has been **executed and inspected**, not just queued:

1. Confirm the engine path is set (`getOption("babelmixr2.nonmem")` etc.) and the binary is on `PATH`. If it is missing, tell the user instead of launching a doomed run.
2. Run `nlmixr(...)` with the chosen `est=`. Capture stdout/stderr — engine errors surface here.
3. After the run, inspect: `print(fit)`, `fit$parFixed`, an `augPred()` plot or VPC. Verify the OFV / objective is finite and parameters are sane.
4. *Then* report results.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `could not find NONMEM` / `could not find Monolix` | `runCommand` not set or wrong; check `getOption("babelmixr2.nonmem")` |
| Run launches but exits with rounding errors | model didn't converge — same fix as in NONMEM directly; consider `nonmemControl(readRounding = TRUE)` to read partial results |
| Fit object missing standard errors / `$parFixed` empty | reading the engine output back failed (e.g. no covariance step ran) — check the engine's own output files, or load the run independently with `nonmem2rx()` / `monolix2rx()` |
| Parameter estimates differ from a hand-written ctl | check transforms — babelmixr2 generates `MU`-referenced code; manual ctls often don't |
| Monolix run "succeeds" but no fit | `lixoftConnectors` not installed *and* `babelmixr2.monolix` option unset |
| `saemix` fails with "non-numeric argument to function" or "invalid subscript type 'list'" | `linCmt()` model, or a theta without an eta ([#212](https://github.com/nlmixr2/babelmixr2/issues/212)); rewrite as ODEs with an eta on every structural parameter |
| `pseudoOptim` "requires all parameters to have finite lower and upper bounds" | give every `ini()` parameter bounds: `tcl <- c(-5, 1, 5)` |
| PKNCA result has no concentrations | unit args (`concu`, `doseu`, `timeu`, `volumeu`) missing or inconsistent with the dataset |

## What NOT to do

- Don't rewrite the model in NONMEM control-stream syntax by hand. The whole point of babelmixr2 is to *not* do that.
- Don't trust a fit you haven't inspected. Engine runs can "succeed" and still produce a degenerate fit object if model import broke.
- Don't mix `est=` between runs without changing `modelName` — output directories will collide.

## In-repo references

- `vignettes/articles/running-nonmem.Rmd` — full NONMEM workflow
- `vignettes/articles/running-monlix.Rmd` — full Monolix workflow
- `vignettes/articles/running-pknca.Rmd` — NCA → popPK initial estimates
- `vignettes/articles/new-estimation.Rmd` — adding a new backend
- `vignettes/articles/PopED.Rmd` — optimal design integration

## Relationship to nonmem2rx and monolix2rx

`babelmixr2` is the *forward* path (nlmixr2 → engine). `nonmem2rx` and `monolix2rx` are the *backward* path (engine output → rxode2/nlmixr2). babelmixr2 does not call the backward translation after the run completes because it already knows what the original nlmixr2 model was.  If a babelmixr2 fit looks broken, the bug is almost always in import — you can debug this by trying to load the engine output directly with `nonmem2rx()` / `monolix2rx()` and seeing if a nlmixr2 fit can be generated from these outputs.
