#' Resolve a Studyflix secret
#'
#' Single entry point for credential resolution. The source is chosen by the
#' SF_SECRET_BACKEND environment variable (spec 5.1, 5.2).
#'
#' @param name Secret name, e.g. "studyflix-billomat-api-key".
#' @param version Version to read. Defaults to "latest". Pin an explicit version
#'   for incident response - a disabled newest version makes "latest" fail
#'   rather than fall back (spec 5.13).
#' @param file_key Only used by the "file" backend: the safer master password.
#' @return The secret value as a UTF-8 character scalar.
#' @export
secret_get <- function(name, version = "latest", file_key = NULL) {
  # ---- start ---- #
  if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)) {
    stop("secret_get(): 'name' must be a non-empty character scalar", call. = FALSE)
  }
  backend <- secretsR_backend()
  secretsR_assert_production_backend(backend)

  cache_key <- paste(backend, name, version, sep = "|")
  cached <- secret_cache_get(cache_key)
  if (!is.null(cached)) return(cached)

  value <- switch(
    backend,
    gsm  = secret_get_gsm(name, version = version),
    env  = secret_get_env(name),
    file = if (is.null(file_key)) secret_get_file(name) else secret_get_file(name, file_key)
  )

  # No backend may hand back something unusable without an error. This is the
  # guard against the NA-returning defect that silently disables authentication.
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    stop(sprintf("secret_get(): backend '%s' returned no usable value for '%s'",
                 backend, name), call. = FALSE)
  }
  secret_cache_set(cache_key, value)
  value
}

#' Refuse non-production backends on a production host
#'
#' Spec 5.2's threat is an actor who can set environment variables for a job.
#' The marker path is therefore NOT env-configurable - otherwise that same actor
#' could point it at a nonexistent file and disable the guard.
#'
#' @param backend The resolved backend name.
#' @return NULL, invisibly.
#' @noRd
secretsR_assert_production_backend <- function(backend) {
  # ---- start ---- #
  if (file.exists(secretsR_production_marker()) && backend != "gsm") {
    stop(sprintf("secret_get(): backend '%s' refused - this host is marked production (%s); only 'gsm' is permitted",
                 backend, secretsR_production_marker()), call. = FALSE)
  }
  if (backend != "gsm") {
    log4r::warn(secretsR_logger(), sprintf("secretsR: using non-gsm backend '%s'", backend))
  }
  invisible(NULL)
}

#' The package logger, built once per process
#'
#' Reuses the package cache rather than a closure, so no `<<-` appears in
#' package code (house rule is a flat ban).
#'
#' @return A log4r logger.
#' @noRd
secretsR_logger <- function() {
  # ---- start ---- #
  lg <- secret_cache_get(".logger")
  if (is.null(lg)) {
    lg <- log4r::logger()
    secret_cache_set(".logger", lg)
  }
  lg
}
