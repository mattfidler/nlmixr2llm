# Startup check: when the package is attached interactively, look at the
# locations the install_* functions write to (Claude Code, Codex, Positron)
# and, if any installed content is out of date relative to this version of the
# package, print a brief notice. It is read-only (never writes), only runs in
# interactive sessions, is wrapped so it can never break package loading, and
# can be disabled with options(nlmixr2llm.startup_check = FALSE).
.onAttach <- function(libname, pkgname) {
  if (!interactive() ||
      !isTRUE(getOption("nlmixr2llm.startup_check", default = TRUE))) {
    return(invisible())
  }
  msg <- tryCatch(
    startup_drift_message(nlmixr2llm_status(quiet = TRUE)),
    error = function(e) NULL
  )
  if (!is.null(msg)) {
    packageStartupMessage(msg)
  }
  invisible()
}
