# Manifest-based sync for the multi-file installers.
#
# `install_claude_code()` and `install_positron(style = "instructions")` write a
# *set* of files into a directory. When the package's content changes between
# versions (an agent renamed, a package dropped), a plain re-install would leave
# the old files behind as orphans. To avoid that, each install root carries a
# manifest recording the relative paths this package installed there, so a later
# re-install can prune files the current version no longer ships -- without ever
# touching files the package did not create.

manifest_filename <- ".nlmixr2llm-manifest"

read_manifest <- function(root) {
  path <- file.path(root, manifest_filename)
  if (!file.exists(path)) {
    return(character())
  }
  entries <- trimws(readLines(path, warn = FALSE, encoding = "UTF-8"))
  entries[nzchar(entries) & !startsWith(entries, "#")]
}

write_manifest <- function(root, rel_paths) {
  path <- file.path(root, manifest_filename)
  rel_paths <- sort(unique(rel_paths))
  writeLines(
    c(
      "# nlmixr2llm install manifest -- do not edit.",
      "# Relative paths installed here by nlmixr2llm; used to prune obsolete",
      "# files (e.g. renamed/removed content) on a later re-install.",
      rel_paths
    ),
    path,
    useBytes = TRUE
  )
  invisible(path)
}

# Reconcile the manifest after an install.
#
# * `root`        install root the manifest lives in.
# * `universe`    every relative path the current package version *could*
#                 install into `root` (across all packages). Anything the
#                 manifest tracks that is not in here is obsolete.
# * `written_rel` relative paths actually written by this install call.
# * `prune`       if `TRUE`, delete obsolete files (and now-empty dirs) from
#                 disk; if `FALSE`, leave them but keep tracking them so a later
#                 `prune = TRUE` can still clean them up.
#
# Returns the relative paths actually removed (character(0) if none).
sync_manifest <- function(root, universe, written_rel, prune = TRUE) {
  old <- read_manifest(root)
  obsolete <- setdiff(old, universe)

  removed <- character()
  if (isTRUE(prune)) {
    for (rel in obsolete) {
      abs <- file.path(root, rel)
      if (file.exists(abs)) {
        unlink(abs)
        removed <- c(removed, rel)
      }
    }
    prune_empty_dirs(root, removed)
    keep <- intersect(old, universe)        # obsolete dropped from tracking
  } else {
    keep <- old                             # keep tracking obsolete for later
  }

  write_manifest(root, c(keep, written_rel))
  removed
}

# Remove directories left empty after pruning (e.g. skills/<pkg>/), but never
# the install root itself.
prune_empty_dirs <- function(root, removed_rel) {
  dirs <- unique(dirname(file.path(root, removed_rel)))
  dirs <- setdiff(dirs, root)
  for (d in dirs) {
    if (dir.exists(d) &&
        length(setdiff(list.files(d, all.files = TRUE), c(".", ".."))) == 0) {
      unlink(d, recursive = TRUE)
    }
  }
}
