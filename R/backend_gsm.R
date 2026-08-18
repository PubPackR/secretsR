SECRETSR_SCOPE <- "https://www.googleapis.com/auth/cloud-platform"

#' Seam around gargle::token_fetch() so tests can mock it
#'
#' testthat cannot mock bindings in another package's namespace.
#'
#' @param scopes OAuth scopes.
#' @param ... Passed to gargle.
#' @return A gargle token, or NULL.
#' @noRd
gargle_token_fetch <- function(scopes, ...) {
  # ---- start ---- #
  gargle::token_fetch(scopes = scopes, ...)
}

#' The pruned credential chain
#'
#' gargle's default chain ends with credentials_user_oauth2, which opens an
#' interactive browser flow - in an unattended FlowForce job that hangs instead
#' of crashing (spec 5.3).
#'
#' NOTE: token_fetch() has no cred_funs argument. Its signature is
#' token_fetch(scopes, ...) and ... is forwarded TO each credential function,
#' not used to select them. Pruning must go through the registry.
#'
#' @return Named list of gargle credential functions.
#' @noRd
secretsR_cred_funs <- function() {
  # ---- start ---- #
  list(
    credentials_app_default = gargle::credentials_app_default,
    credentials_gce         = gargle::credentials_gce
  )
  # Spec 5.3's chain is "{app_default, gce} plus byo_oauth2 for CI". The CI half
  # is NOT implemented here: credentials_byo_oauth2() requires a Token2.0 object
  # in its `token` argument, which token_fetch() cannot supply, so registering it
  # bare produces a function that always fails and is silently skipped - a guard
  # that cannot work. CI is deferred to Plan C3 using spec 5.11 option 2.
}

#' Fetch an Application Default Credentials token for Secret Manager
#'
#' @return A gargle token.
#' @noRd
secretsR_token <- function() {
  # ---- start ---- #
  cached <- secret_cache_get(".token")
  if (!is.null(cached)) {
    # ADC access tokens live ~1 hour. A long-lived Shiny process (spec 5.9)
    # would otherwise serve a stale bearer forever and 401 with no recovery.
    if (inherits(cached, "Token2.0") && isTRUE(try(cached$can_refresh(), silent = TRUE))) {
      try(cached$refresh(), silent = TRUE)
    }
    return(cached)
  }

  # Scoped to this call only. A session-global cred_funs_set() would change
  # behaviour for bigrquery/googlesheets4 running in the same process.
  gargle::local_cred_funs(funs = secretsR_cred_funs(), action = "replace")

  token <- gargle_token_fetch(scopes = SECRETSR_SCOPE)
  if (is.null(token)) {
    stop(paste(
      "no Application Default Credentials found.",
      "On a laptop run: gcloud auth application-default login",
      "On the server set GOOGLE_APPLICATION_CREDENTIALS to the service-account key.",
      sep = "\n"
    ), call. = FALSE)
  }
  secret_cache_set(".token", token)
  token
}

#' Extract the bearer string from a gargle token
#'
#' Separate because gargle's credential classes nest differently.
#'
#' @param tok A gargle token.
#' @return The access token as a character scalar.
#' @noRd
secretsR_access_token <- function(tok) {
  # ---- start ---- #
  if (!is.null(tok$credentials$access_token)) return(tok$credentials$access_token)
  if (!is.null(tok$auth_token$credentials$access_token)) {
    return(tok$auth_token$credentials$access_token)
  }
  stop("could not extract an access token from the gargle credential", call. = FALSE)
}
