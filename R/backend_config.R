#' The credential backend this process will use
#'
#' Exported so a consuming package can branch on the backend without either
#' reaching into `:::` or re-implementing the resolution rules - the two ways a
#' consumer's idea of the backend drifts out of sync with the dispatcher's.
#'
#' `Billomatics` needs it for two decisions. Under `gsm` there is no password to
#' prompt for interactively, and no per-service `file_key` to thread through;
#' under `file` there is. And the four service-account JSON services have no
#' `file` path at all (design 5.7), so they must branch rather than fail.
#'
#' This is a *report*, not a permission: `secret_get()` still enforces the
#' production guard, so a caller learning the backend here cannot use that
#' knowledge to bypass it.
#'
#' @return One of "gsm", "file" or "env", as a character scalar. Errors if
#'   SF_SECRET_BACKEND holds an unrecognised value.
#' @export
#' @examples
#' secret_backend()
secret_backend <- function() {
  # ---- start ---- #
  secretsR_backend()
}

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
#' SF_GSM_PROJECT is honoured only OUTSIDE production. In production the project
#' comes from the service-account key's own project_id, falling back to the
#' compiled-in default.
#'
#' WHAT THIS DOES AND DOES NOT BUY, corrected 2026-09-09. The original note here
#' claimed this stops an actor who can set environment variables for a job from
#' repointing the package at a project they control. It does not, and the Python
#' twin inherited the claim before review caught it.
#'
#' In production the project is read from the file named by
#' GOOGLE_APPLICATION_CREDENTIALS -- an environment variable of exactly the same
#' writability as SF_SECRET_BACKEND. An actor who can set one can set the other,
#' point it at their own valid key, and get their own project back while
#' SF_GSM_PROJECT stays correctly ignored.
#'
#' Nor is that actor meaningfully constrained: on the FlowForce host, whoever can
#' set a job's environment can also edit its command, so they can already run
#' arbitrary code as flow-force-user and print any resolved secret.
#'
#' So this is defence against MISCONFIGURATION -- a stray SF_GSM_PROJECT in a
#' profile or an inherited environment -- not against a hostile job definition.
#' Returning SECRETSR_DEFAULT_PROJECT unconditionally in production would close
#' it, and is a behavioural no-op today because sa-flowforce lives in
#' studyflix-secrets, so its key's project_id already IS the default. Deferred as
#' cleanup rather than done as a fix, because the guard was never load-bearing.
#'
#' The failure it does leave is loud, not silent: a wrong project produces a 403
#' whose message names the project it tried.
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
