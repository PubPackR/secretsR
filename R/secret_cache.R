.secretsR_cache <- new.env(parent = emptyenv())

#' Read a cached value
#'
#' inherits = FALSE is required on both exists() and get(): without it, get()
#' escapes to the package namespace and returns a same-named function.
#'
#' @param key Cache key.
#' @return The cached value, or NULL.
#' @noRd
secret_cache_get <- function(key) {
  # ---- start ---- #
  if (exists(key, envir = .secretsR_cache, inherits = FALSE)) {
    get(key, envir = .secretsR_cache, inherits = FALSE)
  } else {
    NULL
  }
}

#' Store a value in the per-process cache
#'
#' @param key Cache key.
#' @param value Value to cache.
#' @return The value, invisibly.
#' @noRd
secret_cache_set <- function(key, value) {
  # ---- start ---- #
  assign(key, value, envir = .secretsR_cache)
  invisible(value)
}

#' Empty the per-process secret cache
#'
#' Exported so a long-running process (a Shiny app, a scheduled job) can pick up
#' a rotated secret without a restart - otherwise spec 5.13's rotation story
#' cannot reach anything already running.
#'
#' @return NULL, invisibly.
#' @export
secret_cache_clear <- function() {
  # ---- start ---- #
  rm(list = ls(.secretsR_cache, all.names = TRUE), envir = .secretsR_cache)
  invisible(NULL)
}
