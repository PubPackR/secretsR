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

#' Seam around the HTTP round trip so tests can mock it
#'
#' @param req An httr2 request.
#' @return The parsed JSON body.
#' @noRd
gsm_perform <- function(req) {
  # ---- start ---- #
  httr2::resp_body_json(httr2::req_perform(req))
}

#' Read a secret from Google Secret Manager
#'
#' @param name Secret name.
#' @param version Version to read. "latest" resolves to the highest version
#'   number regardless of state - a disabled newest version makes access fail
#'   rather than fall back, so pin an explicit version for incident response
#'   (spec 5.13).
#' @return Secret value as a UTF-8 character scalar.
#' @noRd
secret_get_gsm <- function(name, version = "latest") {
  # ---- start ---- #
  project <- secretsR_project()
  url <- sprintf(
    "https://secretmanager.googleapis.com/v1/projects/%s/secrets/%s/versions/%s:access",
    project, name, version
  )
  req <- httr2::request(url)
  req <- httr2::req_auth_bearer_token(req, secretsR_access_token(secretsR_token()))
  # Without an explicit timeout a stalled TLS connection hangs a FlowForce job
  # indefinitely - the same hang-instead-of-crash failure the pruned credential
  # chain prevents.
  req <- httr2::req_timeout(req, seconds = 10)
  # httr2's default is_transient covers 429/503, which is exactly spec 5.10.
  req <- httr2::req_retry(req, max_tries = 3)

  body <- tryCatch(
    gsm_perform(req),
    httr2_http_401 = function(e) {
      # Stale bearer: drop the cached token so the next call re-authenticates.
      secret_cache_set(".token", NULL)
      stop(sprintf("GSM: authentication rejected for '%s'. The cached token was cleared - retry.",
                   name), call. = FALSE)
    },
    httr2_http_403 = function(e) stop(sprintf(
      "GSM: access denied for '%s' in project '%s'. The calling principal needs roles/secretmanager.secretAccessor on this secret.",
      name, project), call. = FALSE),
    httr2_http_404 = function(e) stop(sprintf(
      "GSM: secret '%s' (version %s) not found in project '%s'.",
      name, version, project), call. = FALSE),
    httr2_http_400 = function(e) stop(sprintf(
      "GSM: bad request for '%s' version %s. If the newest version is disabled, 'latest' fails - pin an explicit version.",
      name, version), call. = FALSE)
  )

  data <- body$payload$data
  if (is.null(data) || !is.character(data)) {
    stop(sprintf("GSM: unexpected response shape for '%s' version %s (no payload.data)",
                 name, version), call. = FALSE)
  }
  out <- rawToChar(jsonlite::base64_dec(data))
  # Encoding<- only labels bytes; it never validates. Spec 5.1 calls UTF-8 a
  # contract to enforce, so check before labelling.
  if (!validUTF8(out)) {
    stop(sprintf("GSM: secret '%s' version %s is not valid UTF-8; binary payloads are out of scope (spec 5.1)",
                 name, version), call. = FALSE)
  }
  Encoding(out) <- "UTF-8"
  out
}
