---
name: nlmixr2
description: Use this skill when the user is fitting population PK/PD models with the R package `nlmixr2`. Triggers include writing `ini({}) / model({})` model functions, calling `nlmixr2(model, data, est = ...)`, picking between saem / focei / foce / fo / agq / laplace / nlme / posthoc, configuring `saemControl()` / `foceiControl()`, or post-processing a fit with `augPred()`, `vpcPlot()`, `$parFixed`, `$omega`.
---

# nlmixr2 — population PK/PD modeling in R

`nlmixr2` is the open-source R package for nonlinear mixed-effects modeling. Models share their syntax with `rxode2` (function-style `ini({}) / model({})`), the same model can be fit by several estimation engines (saem, focei, laplace, agq, nlme), and the result is a tidy `nlmixr2` fit object that supports VPCs, augmented predictions, and the usual diagnostics.

## When to use this skill

Activate whenever the user is:

- Writing or editing a function-style nlmixr2 model and fitting it with `nlmixr2(...)`.
- Choosing between saem, focei, agq, or laplace for a given problem, or tuning their controls.
- Running diagnostics on a fit (`augPred`, `vpcPlot`, `$parFixed`, `$omega`, GOF plots).
- Translating a model from another tool (NONMEM, Monolix, mrgsolve)
  into nlmixr2 syntax — usually via `nonmem2rx` / `monolix2rx`,
  followed by `babelmixr2::as.nlmixr2()`. This can also be refit to
  give possibly different results if needed.
- Running the same model across multiple engines via `babelmixr2` (`est = "nonmem"` / `"monolix"`).

## Minimum viable example

```r
library(nlmixr2)

one.compartment <- function() {
  ini({
    tka <- log(1.57); label("Ka")
    tcl <- log(2.72); label("Cl")
    tv  <- log(31.5); label("V")
    eta.ka ~ 0.6
    eta.cl ~ 0.3
    eta.v  ~ 0.1
    add.sd <- 0.7
  })
  model({
    ka <- exp(tka + eta.ka)
    cl <- exp(tcl + eta.cl)
    v  <- exp(tv  + eta.v)
    d/dt(depot)  <- -ka * depot
    d/dt(center) <-  ka * depot - cl / v * center
    cp <- center / v
    cp ~ add(add.sd)
  })
}

fit <- nlmixr2(one.compartment, theo_sd, est = "saem",
               saemControl(print = 0))

print(fit)
fit$parFixed       # population estimates + SE + %RSE + back-transformed
fit$omega          # BSV variance/covariance
augPred(fit)       # individual + population predictions, plottable
vpcPlot(fit)       # visual predictive check
```

Always run the example (or its adapted form) and confirm the fit converges and prints sane parameter values before handing it back.

## Authoring rules

1. **Function-style UI.** A model is an R function returning `ini({}) / model({})`. Hand the function itself (not `model()`) to `nlmixr2()` — `nlmixr2()` instantiates it internally.
2. **Parameterize on the log/logit scale.** Convention: `tka <- log(1.57)` in `ini`, then `ka <- exp(tka + eta.ka)` in `model`. Use `logit()` / `expit()` for parameters bounded to (0, 1), or the expanded `logit(est, low, hi)` / `expit(est, low, hi)` for parameters bounded to (low, hi).
3. **Random effects** use `~` with a starting variance (e.g. `eta.cl ~ 0.3`). Off-diagonal blocks: join the etas with `+` on one line and give a lower-triangular matrix start, e.g. `eta.cl + eta.v ~ c(0.3, 0.01, 0.1)`.
4. **Residual error** lives at the end of `model({})` and uses the rxode2 error functions:
   - `cp ~ add(add.sd)` — additive
   - `cp ~ prop(prop.sd)` — proportional
   - `cp ~ add(add.sd) + prop(prop.sd)` — combined
   - `cp ~ lnorm(lnorm.sd)` — log-normal
   - `cp ~ add(add.sd) + boxCox(lambda)` - Box-Cox + additive
   - `cp ~ add(add.sd) + dt(df)` - t-distribution with `df` degrees of freedom
   - `ll(cp) ~ likelihood` - generalized likelihood for an endpoint
   - Multi-endpoint: one line per endpoint, with a bare `| endpointName` (see below).
5. **Algebraic definitions** (e.g. `cp <- center / v`) must appear before they're used and before the residual error line.
6. **Pick `est=` deliberately:**
   - `"saem"` — robust default for most popPK/popPD problems. It *does* compute standard errors (`saemControl(covMethod = "sa")` is the default). It does not compute the objective function during the fit; the first access to `fit$objf` / `AIC(fit)` triggers a Gaussian-quadrature `-2LL` calculation, and `addCwres()` adds the FOCEi objective plus CWRES.
   - `"focei"` — gradient-based, gives Hessian-based SEs, more sensitive to initial estimates and stiff models, but can be used with generalized likelihood.
   - `"foce"` — FOCE without interaction.
   - `"fo"` — first-order; mostly for legacy comparison.
   - `"laplace"` - agq with 1 quadrature point
   - `"agq"` - More accurate approximation of likelihoods, can be
     controlled by `nAGQ`, but should be low and only be used with a
     model with a small number of between subject variability (etas).
   - `"nlme"` — wraps R's `nlme` package; fine for simple problems.
   - `"posthoc"` — empirical Bayes only; freezes THETAs/OMEGAs and computes ETAs for the given data. Useful after a fit when you have new individuals.
   - `"foi"` — first-order with interaction.

   Newer engines in `nlmixr2est` (each with a matching `<name>Control()`):

   | `est=` | Method |
   |---|---|
   | `"vae"` | Variational autoencoder; supports covariate selection via `vaeControl(covSelectMethod=)` |
   | `"advi"` | Automatic differentiation variational inference |
   | `"npag"` | Nonparametric adaptive grid |
   | `"npb"` | Nonparametric Bayes |
   | `"impmap"` | Importance-sampling EM (with MAP search) |
   | `"imp"` | Importance-sampling EM without MAP search |
   | `"qrpem"` | Quasi-random parametric EM (impmap with `qr=TRUE`, `sir=TRUE`) |

   The FOCEI-family, quadrature, and nonparametric methods also have **mu-referenced** variants with matching `*Control()` functions: `mfocei`/`ifocei`, `mfoce`/`ifoce`, `mfocep`/`ifocep`, `magq`/`iagq`, `mlaplace`/`ilaplace`, `mnpag`/`inpag`, `mnpb`/`inpb`.

   Both prefixes are mu-referenced; they differ only in how mu-referenced population and covariate-coefficient thetas are profiled out of the outer optimizer — `m*` uses an in-C++ OLS regression (`muModel = "lin"`), `i*` uses IRLS (`muModel = "irls"`). **The `i` prefix means IRLS, not interaction.** Tune with `foceiControl(muModel=, muRefCovAlg=, muModelTol=, muModelMaxCycles=, muModelClampRetries=)`.

   A trailing **`f`** marks the *fast* variant — `focef`, `foceif`, `focepf`, `agqf`, and the `m*`/`i*` forms (`mfoceif`, `ifoceif`, `magqf`, `iagqf`, …). These force `foceiControl(fast = TRUE)`, which computes the analytic overall outer gradient (Almquist 2015) and optimizes by gradient descent instead of a derivative-free search. When you haven't picked an `outerOpt` yourself, the default switches from `bobyqa` to the gradient-based `lbfgsb3c`; an explicit `outerOpt` is respected. Prefer these when the model is in analytic scope — same objective, faster convergence.

   The `foceiControl()` `outerOpt` default is **`bobyqa`** (not `nlminb`). Alternatives: `nlminb`, `lbfgsb3c`, `L-BFGS-B`, `mma`, `lbfgsbLG`, `slsqp`, `uobyqa`, `newuoa`.

   `nlmixr2est` registers ~76 `est=` values in total; enumerate them with `methods("nlmixr2Est")` rather than guessing.

   Mixture models via `mix()` are supported for `focei`, `foce`, `foi`, and `fo`.
7. **Always pass a control object** matched to `est`: `saemControl()`, `foceiControl()`, `foceControl()`, `foControl()`, `laplaceControl()`, `agqControl()`, `nlmeControl()`, `posthocControl()`. Set `print = 0` for quieter logs in scripts.
8. **Data format.** Standard NONMEM-style: `ID`, `TIME`, `EVID`, `AMT`, `CMT` (or `cmt` matching compartment names), `DV`, optional covariates. nlmixr2 also accepts compartment names in `CMT` rather than integers.

## Workflow

The skill is "done" only when the model has been **fit, converged, and inspected** — not just written:

1. Write the model function + load data + call `nlmixr2()`.
2. Run it. Capture the convergence summary and OFV.
3. Inspect `print(fit)`, `fit$parFixed` (estimates, SE, %RSE, BSV%, shrinkage), `fit$omega`.
4. Run at least one diagnostic: `augPred(fit)` for individual fits or `vpcPlot(fit)` for predictive performance.
5. Confirm the OFV is finite and **no parameter is hugging a boundary**. A "converged" fit with a parameter sitting at its bound has not really estimated that parameter — rethink the model rather than reporting it.
6. Only then report results.

## Diagnostic / post-processing cheatsheet

```r
fit$parFixed        # population params, SE, %RSE, BSV%, shrinkage (data.frame)
fit$omega           # BSV variance-covariance
fit$objf            # OFV / -2LL
fit$cov             # variance-covariance of fixed effects (if available)
fit$shrink          # shrinkage by ETA

augPred(fit)        # IPRED + PRED + observations
plot(augPred(fit))

vpcPlot(fit, n = 500, show = list(obs_dv = TRUE))   # standard VPC
```

For residual diagnostics use `as.data.frame(fit)` to get the per-row table with `IPRED`, `PRED`, `IWRES`, `CWRES`, `ETA*`.

## Multi-endpoint models

```r
ini({
  # ... structural parameters ...
  pk.sd  <- 0.7      # residual SD for the cp endpoint
  eff.sd <- 10       # residual SD for the effect endpoint
})
model({
  # ...
  cp     <- center / v
  effect <- e0 - emax * cp / (ec50 + cp)
  cp     ~ add(pk.sd)                | cp
  effect ~ add(eff.sd)               | effect
})
```

Every residual-error parameter must be declared in `ini({})` just like a THETA.

Bind each error line to a row category in the dataset's `DVID` column with a **bare endpoint name** after `|`. Do **not** write `| dvid("endpoint")` — that is a hard parse error (`the condition 'dvid("cp")' must be a simple name`), not a deprecation warning.

**Simulating a multi-endpoint model:** every observation record must say which endpoint it belongs to, so a plain sampling grid fails:

```
'dvid'->'cmt' or 'cmt' on observation record or on a undefined compartment (use 'cmt()' 'dvid()')
```

Add one sampling pass per endpoint, each naming its endpoint in `cmt`:

```r
ev <- et(amt = 320, cmt = "depot") |>
  et(seq(0, 48, by = 0.5), cmt = "cp") |>
  et(seq(0, 48, by = 0.5), cmt = "effect")
```

This is a simulation/event-table requirement only — a model that fits fine can still fail here.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `parameter not found` at compile | symbol used in `model({})` not declared in `ini({})`, not a compartment, not in the data |
| SAEM runs forever / huge OFV swings | bad initial estimates, especially on the log scale; sanity-check `exp(tka)` etc. |
| FOCEi fails with Hessian errors | over-parameterized OMEGA, near-zero variance estimate, or identifiability issue — use fewer ETAs, fix small variances, or switch optimizer away from the `bobyqa` default (e.g. `foceiControl(outerOpt = "nlminb")`, or `fast = TRUE` for `lbfgsb3c`) |
| `vpcPlot` empty / wrong | residual error not specified, or the endpoint names after `|` don't match the dataset's `DVID` values |
| `augPred` flat | dosing into wrong compartment, or `cmt=` in data doesn't match `d/dt(name)` |
| `$parFixed` SEs are NA on a SAEM fit | Not expected — SAEM computes SEs by default. Check whether `covMethod = ""` was passed, or whether the covariance step failed (`fit$covMethod` reports what actually ran) |
| Residual-error SE prints as a denormal (`9.39e-323`, `6.95e-310`) | Known bug ([nlmixr2est#816](https://github.com/nlmixr2/nlmixr2est/issues/816)) affecting SAEM `covMethod="sa"` and `"linFim"`. The correct SE is already in `fit$cov` — read `sqrt(diag(fit$cov))[["<par>"]]`. Don't report the `parFixed` value, and don't conclude SEs are unavailable |

## What NOT to do

- Don't invent nlmixr2 syntax. If unsure, check the rxode2 syntax reference (`inst/syntax-functions.csv`) and the nlmixr2 vignettes.
- Don't hand the user pseudocode. Always produce a complete, runnable script with `library(nlmixr2)` and a real dataset.
- Don't skip the fit step. A model that "looks right" but never converged is not delivered.
- Don't rely on default initial estimates — set them on the right scale, and call `label()` on each THETA so the printout is readable.

## References (in the nlmixr2 source repo, github.com/nlmixr2/nlmixr2)

- `vignettes/running_nlmixr.Rmd` — canonical intro
- `vignettes/multiple-endpoints.Rmd` — multi-endpoint specification
- `vignettes/residualErrors.Rmd` — residual error model reference
- `vignettes/addingCovariances.Rmd` — OMEGA covariance blocks
- `vignettes/modelPiping.Rmd` — model composition / piping
- `vignettes/censoring.Rmd` — BLQ / censored observations
- `vignettes/broom.Rmd` — tidying fit objects
- `vignettes/nimo.Rmd`, `mavoglurant.Rmd`, `wbc.Rmd` — worked PK/PD examples
- `vignettes/xgxr-nlmixr-ggpmx.Rmd` — exploratory + GOF plotting workflow

## Relationship to the rest of the ecosystem

- **rxode2** provides the model language and ODE solver underneath; an `nlmixr2` model is an `rxode2` model plus `ini()` and a residual error term.
- **nonmem2rx / monolix2rx** convert NONMEM/Monolix output into objects that can be promoted to nlmixr2 fit-like form for diagnostics in R.
- **babelmixr2** runs the *same* nlmixr2 model function on NONMEM, Monolix, or PKNCA via `est = "nonmem" | "monolix" | "pknca"` and returns an nlmixr2-shaped fit.
