---
name: nlmixr2
description: Use this skill when the user is fitting PK/PD models with the R package `nlmixr2`, either population (mixed-effects) or pooled (no etas). Triggers include writing `ini({}) / model({})` model functions, calling `nlmixr2(model, data, est = ...)`, picking an estimation method (saem, focei and its variants, laplace, agq, imp, impmap, qrpem, npag, npb, emvi, fbvi, vae, nlme, posthoc; nlm/nlminb/bobyqa/optim/trust/... for pooled models; nuts/advi/pathfinder from nlmixr2bayes), putting `prior()` lines in a model, configuring `saemControl()` / `foceiControl()` / `covMethod` / `setCov()`, post-processing a fit with `augPred()`, `vpcPlot()`, `$parFixed`, `$omega`, or simulating from a fit.
---

# nlmixr2 — population PK/PD modeling in R

`nlmixr2` is the open-source R package for nonlinear mixed-effects modeling. Models share their syntax with `rxode2` (function-style `ini({}) / model({})`), the same model can be fit by many estimation methods (see step 6 below), and the result is a tidy `nlmixr2` fit object that supports VPCs, augmented predictions, and the usual diagnostics.

## When to use this skill

Activate whenever the user is:

- Writing or editing a function-style nlmixr2 model and fitting it with `nlmixr2(...)`.
- Choosing an estimation method for a mixed-effects or pooled model, or tuning its control.
- Adding priors for penalized (MAP) or fully Bayesian estimation.
- Simulating from a fit, or piping a fit into a modified model (what-if or adaptive-dosing simulations).
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
3. **Random effects** use `~` with a starting variance (e.g. `eta.cl ~ 0.3`). Off-diagonal blocks: write the etas with `+` and give the lower triangle, e.g. `eta.cl + eta.v ~ c(0.3, 0.01, 0.1)` (var, cov, var). A model with **no** etas is a pooled model; see the pooled methods below.
4. **Residual error** lives at the end of `model({})` and uses the rxode2 error functions:
   - `cp ~ add(add.sd)` — additive
   - `cp ~ prop(prop.sd)` — proportional
   - `cp ~ add(add.sd) + prop(prop.sd)` — combined
   - `cp ~ lnorm(lnorm.sd)` — log-normal
   - `cp ~ add(add.sd) + boxCox(lambda)` - Box-Cox + additive
   - `cp ~ add(add.sd) + dt(df)` - t-distribution with `df` degrees of freedom
   - `ll(cp) ~ likelihood` - generalized likelihood for an endpoint
   - `resp ~ dbinom(1, p)`, `cnt ~ dpois(lambda)` - named distributions; the endpoint name goes on the left of `~`
   - Multi-endpoint: one line per endpoint, optionally with `| endpointName`.
5. **Algebraic definitions** (e.g. `cp <- center / v`) must appear before they're used and before the residual error line.
6. **Pick `est=` deliberately.** The model decides the family: a model with at least one eta needs a mixed-effects method, and a model with none needs a pooled method. The wrong kind errors with "needs to be a mixed effect model" or "can only have population estimates, try 'focei'". `nlmixr2AllEstType()` lists every method in the session, grouped by category.

   *Quick pick:* `saem` when initial estimates are rough or the model is complex, `focei` when estimates are reasonable or you need a generalized likelihood, and a pooled optimizer (below) when there are no etas.

   **Mixed-effects methods**

   | Category | `est=` | Notes |
   |---|---|---|
   | Linearized | `"focei"` | Gradient-based default; covariance `"r,s"`; sensitive to initial estimates and stiffness; supports generalized likelihood |
   | | `"foce"`, `"focep"` | No interaction; `focep` (FOCE+) keeps the residual variance at the conditional eta |
   | | `"fo"`, `"foi"` | First order (with interaction); legacy comparison |
   | | `"nlme"` | Wraps `nlme` (Lindstrom–Bates); simple problems |
   | Integral approx. | `"laplace"` | Laplace (= AGQ with one node) |
   | | `"agq"` | Adaptive Gauss–Hermite quadrature (`nAGQ`); only for models with few etas |
   | | `"imp"`, `"impmap"` | Importance-sampling EM (NONMEM `IMP`); `impmap` centers the proposal at the MAP; covariance `"imp"` |
   | Stochastic EM | `"saem"` | Robust default for most popPK/PD; tolerant of poor initials. Reports SEs (`covMethod = "sa"`) and a -2LL by Gaussian quadrature |
   | | `"qrpem"` | Quasi-random parametric EM (Sobol samples + SIR M-step) |
   | Nonparametric | `"npag"`, `"npb"` | Adaptive grid / nonparametric Bayes for multimodal eta distributions; support points in `fit$npagSupport` |
   | Variational / ML | `"emvi"`, `"fbvi"` | Variational inference, EM-optimized or full-Bayes with flat priors; covariance `"vi"` |
   | | `"vae"` | Variational autoencoder (LSTM encoder, ELBO) with simultaneous covariate selection |
   | Empirical Bayes | `"posthoc"` | Freezes THETA/OMEGA and computes ETAs (MAP) for the given data; useful for new individuals |

   *Variants.* The FOCEi-family names (`foce*`, `laplace`, `agq`) take an `m` prefix (mu-referenced closed-form regression, `muModel = "lin"`), an `i` prefix (mu-referenced IRLS, `muModel = "irls"`), and an `f` suffix (analytic fast outer gradient, `fast = TRUE`). `flaplace`/`fagq` also use the full conditional Hessian (Gaussian endpoints only). Examples: `mfocei`, `ifoceif`, `mlaplace`, `iagqf`. Start with the base method and switch to a variant for speed.

   *From other packages:* babelmixr2 adds `"nlmer"` (`lme4::nlmer`), `"saemix"`, `"nonmem"`, `"monolix"`, and `"pknca"`; nlmixr2bayes adds `"nuts"` (alias `"stan"`), `"advi"`, and `"pathfinder"`, which run Stan and **require a `prior()` on every theta and residual parameter** (OMEGA blocks get a default; see *Priors* below).

   **Pooled methods (no etas)**

   | `est=` | Notes |
   |---|---|
   | `"focei"` | Still works; population likelihood |
   | `"nlm"`, `"nlminb"`, `"n1qn1"`, `"trust"`, `"lbfgsb3c"` | Gradient optimizers with rxode2 sensitivity gradients |
   | `"bobyqa"`, `"newuoa"`, `"uobyqa"` | Derivative-free (bounded / unbounded) |
   | `"optim"` | `stats::optim`; shortcuts `"neldermead"`, `"bfgs"`, `"cg"`, `"lbfgsb"`, `"sann"`, `"brent"` |
   | `"nls"` | Nonlinear least squares; simple models; OFV on a different scale from the others |
   | `"fmeMcmc"`, `"pseudoOptim"` | babelmixr2: FME MCMC (priors in `fmeMcmcControl(prior=)`) and global search (all parameters bounded) |
7. **Always pass a control object** matched to `est`: `saemControl()`, `foceiControl()`, `foceControl()`, `foControl()`, `laplaceControl()`, `agqControl()`, `impmapControl()`, `qrpemControl()`, `npagControl()`, `emviControl()`, `vaeControl()`, `nlmeControl()`, `nlmControl()`, `nlminbControl()`, `bobyqaControl()`, `optimControl()`, and so on. A control alone implies its method (`nlmixr2(mod, data, laplaceControl())`). Set `print = 0` for quieter logs in scripts.
8. **Data format.** Standard NONMEM-style: `ID`, `TIME`, `EVID`, `AMT`, `CMT` (or `cmt` matching compartment names), `DV`, optional covariates. nlmixr2 also accepts compartment names in `CMT` rather than integers.

## Workflow

The skill is "done" only when the model has been **fit, converged, and inspected** — not just written:

1. Write the model function + load data + call `nlmixr2()`.
2. Run it. Capture the convergence summary and OFV.
3. Inspect `print(fit)`, `fit$parFixed` (estimates, SE, %RSE, BSV%, shrinkage), `fit$omega`.
4. Run at least one diagnostic: `augPred(fit)` for individual fits or `vpcPlot(fit)` for predictive performance.
5. Only then report results.

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

## Priors: penalized and Bayesian fits

Priors go in `ini({})` with the same syntax rxode2 uses for uncertainty simulation (see the rxode2 skill for every form):

```r
one.cmt <- function() {
  ini({
    tka <- 0.45; tcl <- log(c(0, 2.7, 100)); tv <- 3.45
    add.sd <- c(0, 0.7)
    eta.ka ~ 0.6; eta.cl ~ 0.3; eta.v ~ 0.1
    prior(tka) ~ dnorm(0.45, 1)
    prior(tcl) ~ dnorm(1, 1)
    prior(tv) ~ dnorm(3.45, 1)
    prior(add.sd) ~ dcauchy(0, 2.5)
  })
  model({
    ka <- exp(tka + eta.ka); cl <- exp(tcl + eta.cl); v <- exp(tv + eta.v)
    linCmt() ~ add(add.sd)
  })
}
fitMap  <- nlmixr2(one.cmt, theo_sd, "focei")     # MAP: -2 log p(theta, omega) added to the objective
library(nlmixr2bayes)
fitNuts <- nlmixr2(one.cmt, theo_sd, "nuts", nutsControl(seed = 42, chains = 2, iter = 1000))
```

- **A prior is never silently ignored.** The FOCEi family (all variants), `laplace`/`agq`, and `imp`/`impmap`/`qrpem` use them as a penalty; `nuts`/`advi`/`pathfinder` use them as the Bayesian prior; `posthoc` evaluates them. Every other method (`saem`, `nlme`, `npag`, `vae`, the pooled optimizers, NONMEM/Monolix via babelmixr2, ...) refuses a model with priors.
- The prior convention (`"general"`, NONMEM `"nwpri"`, `"tnpri"`) is auto-detected from what the model wrote; force it with `foceiControl(priorMethod = )`.
- To simulate uncertainty from a fit that carries priors, pass `usePrior = FALSE`, e.g. `rxSolve(fitMap, ev, nStud = 100, usePrior = FALSE)`. The fitted estimates no longer match the prior means, which the prior simulation requires.
- nlmixr2bayes refuses a model without priors and prints suggested `prior()` lines. OMEGA blocks without a prior get an announced LKJ(2) + half-Cauchy default.

## Covariance step

`fit$cov` covers every estimated parameter: thetas, residual error, and omega (named `om.eta.cl`, `cov.eta.cl.eta.v`). `fix()`ed, IOV, and mixture-probability parameters are excluded. Choose the method with `covMethod =` in the control, or switch a finished fit without refitting (results are cached):

```r
setCov(fit, "analytic")   # exact observed information (NONMEM MATRIX=R, but exact)
setCov(fit, "sa")         # SAEM Louis stochastic approximation, on any mixed-effects fit
setCov(fit, "imp")        # importance-sampling observed information
```

Other tokens: `"r,s"` (sandwich, FOCEi-family default), `"r"`, `"s"`, `"vi"` (emvi/fbvi only), `"nlme"` (nlme only), `"linFim"`/`"fim"` (saem only), and `""` (skip). A method that cannot be computed for a fit (e.g. `"analytic"` on a prior-penalized fit) errors and leaves the current covariance in place. If two methods disagree on an SE, find out why before reporting it.

## Simulating from a fit and piping

```r
ev <- et(amt = 320, cmt = "depot") |> et(seq(0, 48, by = 1))
rxSolve(fit, ev, nSub = 100)               # new subjects from the final estimates
rxSolve(fit, ev, nSub = 100, nStud = 20)   # + uncertainty: thetaMat = fit$cov, dfSub/dfObs from the data
simulate(fit, nsim = 100)                  # replicate the original dataset (VPC-style)

wt   <- fit |> model(cl <- exp(tcl + eta.cl) * (WT/70)^0.75)   # starts from the final estimates
what <- fit |> ini(tka = log(3))                                  # what-if value
```

Piping a fit returns an rxode2 model whose `ini()` holds the fitted estimates and leaves `fit` untouched. That makes it the right way to attach an adaptive-dosing protocol (`model({...}, append = TRUE, auto = FALSE)`) or a new scenario to a qualified model. See the rxode2 skill for adaptive dosing and uncertainty options.

## Multi-endpoint models

```r
model({
  # ...
  cp     <- center / v
  effect <- e0 - emax * cp / (ec50 + cp)
  cp     ~ add(prop.sd)              | cp
  effect ~ add(eff.sd)               | effect
})
```

Use  `| endpoint` (do NOT use `dvid("endpoint")`) to bind each error line to a row category in the dataset's `DVID` column.

## Debugging quick reference

| Symptom | Likely cause |
|---|---|
| `parameter not found` at compile | symbol used in `model({})` not declared in `ini({})`, not a compartment, not in the data |
| SAEM runs forever / huge OFV swings | bad initial estimates, especially on the log scale; sanity-check `exp(tka)` etc. |
| Model with priors errors on `est=` | that method cannot use priors; use a FOCEi-family, `imp`/`impmap`/`qrpem`, or nlmixr2bayes method |
| "needs to be a mixed effect model" / "can only have population estimates" | wrong family for the model; see the pooled vs mixed-effects tables |
| FOCEi fails with Hessian errors | over-parameterized OMEGA, near-zero variance estimate, or model identifiability issue — try fewer ETAs or fix small variances, or try other outerOpt optimizations like `foceiControl(outerOpt="bobyqa")` for instance |
| `vpcPlot` empty / wrong | residual error not specified, or endpoint names after `|` don't match the data's `DVID` values |
| `augPred` flat | dosing into wrong compartment, or `cmt=` in data doesn't match `d/dt(name)` |
| Output looks fine but `$parFixed` SEs are NA | covariance step failed or was skipped; try `setCov(fit, "analytic")` or `setCov(fit, "sa")` instead of refitting |

## What NOT to do

- Don't invent nlmixr2 syntax. If unsure, check the rxode2 syntax reference (`inst/syntax-functions.csv`) and the nlmixr2 vignettes.
- Don't hand the user pseudocode. Always produce a complete, runnable script with `library(nlmixr2)` and a real dataset.
- Don't skip the fit step. A model that "looks right" but never converged is not delivered.
- Don't rely on default initial estimates — set them on the right scale, and call `label()` on each THETA so the printout is readable.

## In-repo references

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
- **babelmixr2** runs the *same* nlmixr2 model function on NONMEM, Monolix, or PKNCA via `est = "nonmem" | "monolix" | "pknca"`, adds in-R backends (`nlmer`, `saemix`, `fmeMcmc`, `pseudoOptim`), and builds PopED designs (`est = "poped"`), returning an nlmixr2-shaped fit.
- **nlmixr2bayes** adds Stan-based Bayesian estimation (`est = "nuts" | "advi" | "pathfinder"`) driven by the model's `prior()` lines.
