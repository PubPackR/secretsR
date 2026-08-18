#' Resolve the active secret backend
#'
#' Reads SF_SECRET_BACKEND. Per-process by design (spec 5.2) - never set this
#' machine-wide.
#'
#' @return One of "gsm", "file", "env".
#' @noRd
secretsR_backend <- function() {
  # ---- start ---- #
  backend <- Sys.getenv("SF_SECRET_BACKEND", unset = "")
  if (!nzchar(backend)) backend <- "file"
  valid <- c("gsm", "file", "env")
  if (!backend %in% valid) {
    stop(sprintf("SF_SECRET_BACKEND must be one of %s, got '%s'",
                 paste(valid, collapse = "/"), backend), call. = FALSE)
  }
  backend
}

#' Resolve the Google Cloud project holding the secrets
#'
#' Sys.getenv()'s unset= only fires when the variable is genuinely absent, so a
#' set-but-empty variable is handled explicitly - otherwise SF_GSM_PROJECT=""
#' would build a URL like .../projects//secrets/...
#'
#' @return Project id as a character scalar.
#' @noRd
secretsR_project <- function() {
  # ---- start ---- #
  project <- Sys.getenv("SF_GSM_PROJECT", unset = "")
  if (!nzchar(project)) "studyflix-secrets" else project
}

#' Path to the production marker file
#'
#' Deliberately a function rather than an environment variable: spec 5.2's threat
#' model is an actor who can set environment variables for a job, so an
#' env-configurable marker path would let that same actor disable the guard.
#' Tests override this with local_mocked_bindings().
#'
#' @return Absolute path to the marker file.
#' @noRd
secretsR_production_marker <- function() {
  # ---- start ---- #
  "/etc/studyflix/production"
}
