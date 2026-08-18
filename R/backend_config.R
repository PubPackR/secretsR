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

#' Is this a production runtime?
#'
#' Two independent signals, because either alone leaves a gap:
#'
#'   1. The marker file. Absent inside the Shiny container, which mounts neither
#'      /etc/studyflix nor an environment block (spec 3.4) - so on its own this
#'      guard is inert on the internet-facing host, i.e. fail-open.
#'   2. A readable service-account key at GOOGLE_APPLICATION_CREDENTIALS. This
#'      travels with the deployment by construction: an actor who can set
#'      environment variables cannot remove it without also breaking
#'      authentication entirely.
#'
#' @return TRUE if either signal is present.
#' @noRd
secretsR_is_production <- function() {
  # ---- start ---- #
  if (file.exists(secretsR_production_marker())) return(TRUE)
  gac <- Sys.getenv("GOOGLE_APPLICATION_CREDENTIALS", unset = "")
  nzchar(gac) && file.exists(gac)
}

#' Resolve the Google Cloud project holding the secrets
#'
#' SF_GSM_PROJECT is honoured only OUTSIDE production. Spec 5.2's threat is an
#' actor who can set environment variables for a job; leaving the project pointer
#' configurable would let that actor satisfy the backend guard with
#' SF_SECRET_BACKEND=gsm and then repoint the whole package at a project they
#' control. In production the project comes from the service-account key's own
#' project_id, falling back to the compiled-in default.
#'
#' Sys.getenv()'s unset= only fires when the variable is genuinely absent, so a
#' set-but-empty variable is handled explicitly.
#'
#' @return Project id as a character scalar.
#' @noRd
secretsR_project <- function() {
  # ---- start ---- #
  if (!secretsR_is_production()) {
    project <- Sys.getenv("SF_GSM_PROJECT", unset = "")
    if (nzchar(project)) return(project)
    return(SECRETSR_DEFAULT_PROJECT)
  }
  from_key <- secretsR_project_from_key()
  if (!is.null(from_key)) from_key else SECRETSR_DEFAULT_PROJECT
}

SECRETSR_DEFAULT_PROJECT <- "studyflix-secrets"

#' Read project_id out of the service-account key, if there is one
#'
#' @return Project id, or NULL.
#' @noRd
secretsR_project_from_key <- function() {
  # ---- start ---- #
  gac <- Sys.getenv("GOOGLE_APPLICATION_CREDENTIALS", unset = "")
  if (!nzchar(gac) || !file.exists(gac)) return(NULL)
  parsed <- tryCatch(jsonlite::fromJSON(gac), error = function(e) NULL)
  if (is.null(parsed) || is.null(parsed$project_id)) return(NULL)
  parsed$project_id
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
