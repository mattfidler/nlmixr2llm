# nlmixr2llm (development version)

## Content corrections

Verified the agent and skill content against rxode2 5.1.3, nlmixr2 6.0.0,
nlmixr2est 7.0.0, babelmixr2 0.1.11.9000, nonmem2rx 0.1.10, and monolix2rx
0.0.6 by executing the documented examples rather than reading them.

* The `nlmixr2verse` agent told models to bind multi-endpoint residual-error
  lines with `| dvid("name")`. That is a hard parse error, not a deprecation.
  Both the agent and the `nlmixr2` skill now document the bare `| endpoint`
  form and warn against `dvid()` explicitly.
* Removed the claim that SAEM does not compute standard errors. It does —
  `saemControl(covMethod = "sa")` is the default and populates SE/%RSE. The
  genuine quirk (the residual-error row's SE is not meaningfully estimated and
  can print as a denormal) is now documented in its place. The objective
  function is described accurately as computed lazily by Gaussian quadrature.
* Propagated the babelmixr2 back-translation correction to the agent and to the
  `nonmem2rx` / `monolix2rx` skills, which still described the old behavior.
  babelmixr2 uses those packages' low-level output readers (`nminfo()`,
  `nmext()`, `nmtab()`, `nmcov()`, `nmxml()`) but does not run the full model
  back-translation.
* Added `babelmixr2::as.nlmixr2()` to the agent as the documented route from a
  `nonmem2rx()` / `monolix2rx()` object to a real nlmixr2 fit.
* Agent gained the `agq` and `laplace` estimation methods, the remaining
  control-object constructors, and the `boxCox()` / `dt()` / `ll()`
  residual-error forms it was missing relative to the skills.
* Documented babelmixr2's other registered backends (`poped`, `saemix`,
  `nlmer`, `fmeMcmc`, `pseudoOptim`).
* Documented that `nonmem2rx()` only populates `$etaData` when
  `validate = TRUE`; the ETA-resampling recipe fails confusingly without it.
* Documented the newer `nlmixr2est` estimation methods that were missing
  entirely: `vae` (variational autoencoder), `advi`, `npag` / `npb`
  (nonparametric), `impmap` / `imp` / `qrpem` (importance-sampling EM), and
  `foi`. Content now points at `methods("nlmixr2Est")` (~76 registered values)
  instead of implying the listed handful is exhaustive. Noted `mix()` mixture
  support for `focei` / `foce` / `foi` / `fo`.
* Documented the estimation-method name modifiers, which were absent:
  - `m` / `i` prefix — both mu-referenced, differing only in the regression
    that profiles mu thetas out of the outer optimizer (`m*` in-C++ OLS,
    `muModel = "lin"`; `i*` IRLS, `muModel = "irls"`). The `i` is **not**
    interaction.
  - `f` suffix — fast variants (`foceif`, `focef`, `agqf`, `mfoceif`, …) that
    force `foceiControl(fast = TRUE)`: analytic overall outer gradient
    (Almquist 2015) with gradient-descent optimization.
* Corrected the FOCEi outer-optimizer default to `bobyqa` (it is no longer
  `nlminb`), listed the alternatives, and fixed a debugging tip that suggested
  switching to `bobyqa` — which is now the default it was already using. Under
  `fast = TRUE` a defaulted `outerOpt` becomes `lbfgsb3c`.
* rxode2 skill: explain the `centr` → `central` rename properly. It is not a
  quirk — `rxSolve()` converts a mass-balanced linear ODE system to the
  analytic `linCmt()` solved form (`odeToLin()` / `linToOde()`), which uses
  canonical compartment names. `mod$state` keeps the ODE names because the UI
  keeps the ODE form. Dosing a renamed-away compartment silently declines the
  conversion and costs the analytic speedup, so spelling it `central` is the
  way to keep it.
* Recorded the residual-error SE denormal as a known upstream bug
  (nlmixr2est#816) rather than expected behavior, with the workaround: the
  correct SE is already in `fit$cov`, so read `sqrt(diag(fit$cov))`.
* Fixed `as.nlmxir2()` typo, an undeclared/misnamed residual-error parameter in
  the multi-endpoint example, and reference headings that said "in this repo"
  when the installed skills live outside any repo.

# nlmixr2llm 0.1.0

* Initial version.
* Ships a single combined `nlmixr2verse` agent spanning the nlmixr2
  pharmacometrics ecosystem (`rxode2`, `nlmixr2`, `nonmem2rx`, `monolix2rx`,
  `babelmixr2`), plus one skill per package.
* Accessor functions: `list_packages()`, `list_agents()`, `list_skills()`,
  `get_agent()`, `get_skill()`, and `system_prompt()` for use as a system
  prompt with any LLM client.
* Installer functions write the content into the locations expected by Claude
  Code (`install_claude_code()`), OpenAI Codex CLI (`install_codex()`),
  Positron Assistant (`install_positron()`), and any tool that reads
  `AGENTS.md` (`install_agents_md()`). Multi-file installers track what they
  write in a manifest and can prune content the package no longer ships.
* `nlmixr2llm_status()` reports whether the content installed into each target
  is up to date with the package.
