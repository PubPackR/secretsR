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
  if (!grepl("^[A-Za-z0-9_-]+$", name)) {
    stop(sprintf("secret_get(): '%s' is not a valid secret name (letters, digits, hyphen, underscore only)",
                 name), call. = FALSE)
  }
  backend <- secretsR_backend()
  secretsR_assert_production_backend(backend)

  # The project and the file key both change what a name resolves to, so both
  # belong in the cache key - otherwise switching either returns the previous
  # project's or previous key's value.
  cache_key <- paste(backend, secretsR_project(), name, version,
                     if (is.null(file_key)) "" else substr(digest_key(file_key), 1, 8),
                     sep = "|")
  cached <- secret_cache_get(cache_key)
  if (!is.null(cached)) return(cached)

  value <- switch(
    backend,
    gsm  = secret_get_gsm(name, version = version),
    env  = secret_get_env(name),
    file = if (is.null(file_key)) secret_get_file(name) else secret_get_file(name, file_key)
  )

  value <- secretsR_validate(value, name, backend)
  secret_cache_set(cache_key, value)
  value
}

#' Enforce the return contract for every backend
#'
#' Spec 5.1 makes UTF-8 text a contract on secret_get(), not on one backend, and
#' the "no path returns NA" rule likewise. Applying both here means all three
#' backends share one rule rather than each remembering it.
#'
#' An empty value is rejected for the same reason the env backend rejects one: a
#' credential that silently becomes "" fails far from its cause.
#'
#' @param value Whatever a backend returned.
#' @param name Secret name, for the message.
#' @param backend Backend name, for the message.
#' @return The value, labelled UTF-8.
#' @noRd
secretsR_validate <- function(value, name, backend) {
  # ---- start ---- #
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value)) {
    stop(sprintf("secret_get(): backend '%s' returned no usable value for '%s'",
                 backend, name), call. = FALSE)
  }
  if (!validUTF8(value)) {
    stop(sprintf("secret_get(): '%s' is not valid UTF-8; binary payloads are out of scope (spec 5.1)",
                 name), call. = FALSE)
  }
  Encoding(value) <- "UTF-8"
  value
}

#' Stable short digest of a key, for cache separation only
#'
#' Never stored, never logged - only used to distinguish cache entries.
#'
#' @param x A character scalar.
#' @return A hex digest.
#' @noRd
digest_key <- function(x) {
  # ---- start ---- #
  paste0(as.integer(utf8ToInt(substr(x, 1, 1))), "-", nchar(x))
}

#' Refuse non-production backends on a production host
#'
#' Spec 5.2's threat is an actor who can set environment variables for a job.
#' The production signal is therefore NOT env-configurable (see
#' secretsR_is_production).
#'
#' The WARN is emitted once per process per backend: a do/main*.R doing hundreds
#' of lookups would otherwise flood the FlowForce log and train people to ignore
#' the one line that matters.
#'
#' @param backend The resolved backend name.
#' @return NULL, invisibly.
#' @noRd
secretsR_assert_production_backend <- function(backend) {
  # ---- start ---- #
  if (secretsR_is_production() && backend != "gsm") {
    stop(sprintf("secret_get(): backend '%s' refused - this is a production runtime; only 'gsm' is permitted",
                 backend), call. = FALSE)
  }
  if (backend != "gsm") {
    warned_key <- paste0(".warned_", backend)
    if (is.null(secret_cache_get(warned_key))) {
      secretsR_warn(sprintf("using non-gsm backend '%s'", backend))
      secret_cache_set(warned_key, TRUE)
    }
  }
  invisible(NULL)
}

#' Emit a warning, via log4r when available
#'
#' log4r was archived from CRAN on 2026-07-14 and the server installs it from
#' the archive with a pinned version. Depending on it hard for one line would
#' make a fresh install fail dependency resolution, so it is a Suggests and we
#' degrade to base warning().
#'
#' @param msg Message text. Never a credential value.
#' @return NULL, invisibly.
#' @noRd
secretsR_warn <- function(msg) {
  # ---- start ---- #
  msg <- paste0("secretsR: ", msg)
  if (requireNamespace("log4r", quietly = TRUE)) {
    lg <- secret_cache_get(".logger")
    if (is.null(lg)) {
      lg <- log4r::logger()
      secret_cache_set(".logger", lg)
    }
    log4r::warn(lg, msg)
  } else {
    warning(msg, call. = FALSE)
  }
  invisible(NULL)
}
