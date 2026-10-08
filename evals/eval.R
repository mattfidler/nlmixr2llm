# Evaluate the nlmixr2llm agent and skills with vitals.
#
# The question is whether the bundled content makes a model better at
# nlmixr2 work. Each sample in evals/dataset.R is answered under two
# conditions with the same model:
#
#   baseline  no system prompt
#   skills    nlmixr2llm::system_prompt(references = TRUE): the agent, every
#             skill and every reference file
#
# Answers are graded by a model against the sample's target (C / P / I).
# Samples with `runs = TRUE` must contain R code, and the code is executed in
# a fresh R process: an answer whose code does not run is marked down one
# grade (C -> P, P -> I) however good its prose is.
#
# Run from the package root:
#
#   Rscript evals/eval.R
#
# Configuration (environment variables, all optional):
#
#   NLMIXR2LLM_EVAL_SOLVER   model under test, as "provider/model" for
#                            ellmer::chat(); default "anthropic/claude-opus-5-5"
#   NLMIXR2LLM_EVAL_GRADER   grading model; default "anthropic/claude-opus-5-5".
#                            A different model family from the solver, e.g.
#                            "google_gemini/gemini-3.5-flash", reduces
#                            self-preference in grading.
#   NLMIXR2LLM_EVAL_IDS      comma-separated sample ids to run (default: all)
#   NLMIXR2LLM_EVAL_EPOCHS   repeats per sample (default 1; use 3+ to see variance)
#   NLMIXR2LLM_EVAL_CONDITIONS  comma-separated subset of "baseline,skills"
#
# Provider credentials come from the usual variables (ANTHROPIC_API_KEY,
# GEMINI_API_KEY, OPENAI_API_KEY, ...). Logs are written to evals/logs/ and
# can be browsed with vitals::vitals_view("evals/logs").

eval_root <- function() {
  root <- getwd()
  if (!file.exists(file.path(root, "evals", "dataset.R"))) {
    stop("Run from the nlmixr2llm package root (evals/dataset.R not found).", call. = FALSE)
  }
  root
}

eval_setting <- function(name, default) {
  value <- Sys.getenv(name, "")
  if (nzchar(value)) value else default
}

# The content under test is the working tree, not an installed copy, so an
# edit to a skill is evaluated without reinstalling the package.
eval_system_prompt <- function(root = eval_root()) {
  if (requireNamespace("pkgload", quietly = TRUE)) {
    pkgload::load_all(root, quiet = TRUE, export_all = FALSE)
  }
  nlmixr2llm::system_prompt(references = TRUE)
}

eval_conditions <- function(root = eval_root()) {
  all <- list(baseline = NULL, skills = eval_system_prompt(root))
  keep <- strsplit(eval_setting("NLMIXR2LLM_EVAL_CONDITIONS", "baseline,skills"), ",")[[1]]
  all[intersect(trimws(keep), names(all))]
}

eval_chat <- function(spec, system_prompt = NULL) {
  ellmer::chat(spec, system_prompt = system_prompt)
}

# ---------------------------------------------------------------------------
# Executing answer code

# Fenced R blocks (```r, ```R, ```{r ...}) from a model answer, in order.
extract_r_code <- function(text) {
  m <- regmatches(text, gregexpr("(?s)```[ \t]*(\\{[rR][^}]*\\}|[rR])[ \t]*\n(.*?)```", text,
                                 perl = TRUE))[[1]]
  if (!length(m)) return(character())
  sub("^```[^\n]*\n", "", sub("```$", "", m))
}

# Run an answer's R code in a fresh R process with the nlmixr2 stack on the
# search path. Returns list(ok, error, seconds).
run_answer_code <- function(text, timeout = 900) {
  code <- extract_r_code(text)
  if (!length(code)) {
    return(list(ok = FALSE, error = "answer contains no fenced R code", seconds = 0))
  }
  dir <- tempfile("nlmixr2llm-eval-")
  dir.create(dir)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)
  file <- file.path(dir, "answer.R")
  writeLines(c("suppressPackageStartupMessages(library(nlmixr2))", code), file)
  start <- Sys.time()
  res <- tryCatch({
    callr::r(function(f) {
      grDevices::pdf(NULL)              # plots go nowhere
      source(f, echo = FALSE)
      invisible(TRUE)
    }, args = list(f = file), wd = dir, timeout = timeout, stdout = NULL, stderr = NULL)
    list(ok = TRUE, error = NA_character_)
  }, error = function(e) {
    msg <- conditionMessage(e)
    if (!is.null(e$parent)) msg <- conditionMessage(e$parent)
    list(ok = FALSE, error = msg)
  })
  res$seconds <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  res
}

# ---------------------------------------------------------------------------
# Scoring

downgrade <- function(score) {
  lv <- levels(score)
  idx <- pmax(match(as.character(score), lv) - 1L, 1L)
  factor(lv[idx], levels = lv, ordered = TRUE)
}

# Model-graded against the target (with partial credit), then capped when
# required code does not run. Both outcomes are kept in scorer_metadata.
nlmixr2_scorer <- function(grader_chat) {
  graded_qa <- vitals::model_graded_qa(partial_credit = TRUE, scorer_chat = grader_chat)
  function(samples, ...) {
    graded <- graded_qa(samples)
    score <- graded$score
    runs <- if ("runs" %in% names(samples)) as.logical(samples$runs) else rep(FALSE, nrow(samples))
    execution <- vector("list", nrow(samples))
    for (i in seq_len(nrow(samples))) {
      if (isTRUE(runs[i])) {
        execution[[i]] <- run_answer_code(samples$result[i])
        if (!execution[[i]]$ok) score[i] <- downgrade(score[i])
      }
    }
    metadata <- Map(function(m, ex) c(m, list(model_grade = NULL, execution = ex)),
                    graded$scorer_metadata, execution)
    for (i in seq_along(metadata)) metadata[[i]]$model_grade <- as.character(graded$score[i])
    list(score = score, scorer_chat = graded$scorer_chat, scorer_metadata = metadata)
  }
}

# Numeric summary: C = 1, P = 0.5, I = 0.
score_value <- function(score) c(I = 0, P = 0.5, C = 1)[as.character(score)]

# ---------------------------------------------------------------------------
# Running

run_nlmixr2_eval <- function(solver = eval_setting("NLMIXR2LLM_EVAL_SOLVER", "anthropic/claude-opus-5-5"),
                             grader = eval_setting("NLMIXR2LLM_EVAL_GRADER", "anthropic/claude-opus-5-5"),
                             ids = eval_setting("NLMIXR2LLM_EVAL_IDS", ""),
                             epochs = as.integer(eval_setting("NLMIXR2LLM_EVAL_EPOCHS", "1")),
                             log_dir = file.path(eval_root(), "evals", "logs")) {
  root <- eval_root()
  source(file.path(root, "evals", "dataset.R"), local = TRUE)
  dataset <- nlmixr2_eval_dataset()
  if (nzchar(ids)) {
    want <- trimws(strsplit(ids, ",")[[1]])
    unknown <- setdiff(want, dataset$id)
    if (length(unknown)) stop("Unknown sample ids: ", paste(unknown, collapse = ", "), call. = FALSE)
    dataset <- dataset[dataset$id %in% want, ]
  }
  dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)
  scorer <- nlmixr2_scorer(eval_chat(grader))

  tasks <- list()
  for (cond in names(conditions <- eval_conditions(root))) {
    message(sprintf("== %s: %d samples x %d epoch(s), solver %s, grader %s",
                    cond, nrow(dataset), epochs, solver, grader))
    tsk <- vitals::Task$new(
      dataset = dataset,
      solver  = vitals::generate(eval_chat(solver, conditions[[cond]])),
      scorer  = scorer,
      name    = paste0("nlmixr2llm-", cond),
      dir     = log_dir
    )
    tsk$eval(epochs = epochs, view = FALSE)
    tasks[[cond]] <- tsk
  }

  samples <- do.call(rbind, lapply(names(tasks), function(cond) {
    s <- tasks[[cond]]$get_samples()
    data.frame(condition = cond, id = s$id, skill = s$skill,
               score = as.character(s$score), value = score_value(s$score),
               row.names = NULL)
  }))
  summary <- stats::aggregate(value ~ condition, data = samples, FUN = mean)
  names(summary)[2] <- "mean_score"
  by_id <- stats::reshape(
    stats::aggregate(value ~ condition + id, data = samples, FUN = mean),
    idvar = "id", timevar = "condition", direction = "wide"
  )
  list(summary = summary, by_id = by_id, samples = samples, tasks = tasks)
}

if (sys.nframe() == 0L) {
  res <- run_nlmixr2_eval()
  cat("\nMean score by condition (C = 1, P = 0.5, I = 0):\n")
  print(res$summary, row.names = FALSE)
  cat("\nMean score by sample:\n")
  print(res$by_id, row.names = FALSE)
  cat("\nLogs: evals/logs (vitals::vitals_view(\"evals/logs\"))\n")
}
