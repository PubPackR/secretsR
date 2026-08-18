SECRETSR_SCOPE <- "https://www.googleapis.com/auth/cloud-platform"
SECRETSR_TOKEN_MAX_AGE_MINS <- 50

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
#' not used to select them. Pruning must go through the registry, and must use
#' local_cred_funs() rather than cred_funs_set(): a session-global set would
#' permanently strip the chain for bigrquery/googlesheets4 in the same process.
#'
#' Spec 5.3's chain is "{app_default, gce} plus byo_oauth2 for CI". The CI half
#' is NOT implemented: credentials_byo_oauth2() requires a Token2.0 object in its
#' token argument, which token_fetch() cannot supply, so registering it bare
#' produces a function that always fails and is silently skipped. CI is deferred
#' to Plan C3 using spec 5.11 option 2.
#'
#' @return Named list of gargle credential functions.
#' @noRd
secretsR_cred_funs <- function() {
  # ---- start ---- #
  list(
    credentials_app_default = gargle::credentials_app_default,
    credentials_gce         = gargle::credentials_gce
  )
}

#' Is the cached token old enough to need refreshing?
#'
#' Based on our own mint timestamp rather than the token's can_refresh(), which
#' is hardcoded TRUE for TokenServiceAccount and always TRUE for an
#' authorized_user ADC. Refreshing on every cache miss would sign a fresh JWT and
#' POST to Google once per secret, reintroducing on the auth side the network
#' dependency spec 5.10 asks us to memoise away.
#'
#' @return TRUE if the token should be refreshed or re-minted.
#' @noRd
secretsR_token_stale <- function() {
  # ---- start ---- #
  minted <- secret_cache_get(".token_minted_at")
  if (is.null(minted)) return(TRUE)
  as.numeric(difftime(Sys.time(), minted, units = "mins")) > SECRETSR_TOKEN_MAX_AGE_MINS
}

#' Explain why no credential could be obtained
#'
#' token_fetch() wraps every credential function in tryCatch and returns NULL, so
#' a malformed key, an unreadable key, a revoked key and no key at all are
#' indistinguishable at that point. Without this, every production auth failure
#' would report "run gcloud auth application-default login" - useless on a
#' server, and actively misleading when the real cause is a 0400 key the
#' container uid cannot read.
#'
#' @return A character message. Never contains key contents.
#' @noRd
secretsR_no_credentials_message <- function() {
  # ---- start ---- #
  gac <- Sys.getenv("GOOGLE_APPLICATION_CREDENTIALS", unset = "")
  if (!nzchar(gac)) {
    return(paste(
      "no Application Default Credentials found, and GOOGLE_APPLICATION_CREDENTIALS is not set.",
      "On a laptop run: gcloud auth application-default login",
      "On a server point GOOGLE_APPLICATION_CREDENTIALS at the service-account key.",
      sep = "\n"))
  }
  if (!file.exists(gac)) {
    return(sprintf("GOOGLE_APPLICATION_CREDENTIALS points at '%s', which does not exist.", gac))
  }
  if (file.access(gac, mode = 4) != 0) {
    return(sprintf("GOOGLE_APPLICATION_CREDENTIALS '%s' exists but is not readable by this process (uid mismatch on a 0400 key?).", gac))
  }
  parsed <- tryCatch(jsonlite::fromJSON(gac), error = function(e) NULL)
  if (is.null(parsed) || is.null(parsed$type)) {
    return(sprintf("GOOGLE_APPLICATION_CREDENTIALS '%s' is readable but is not valid service-account key JSON.", gac))
  }
  sprintf(paste(
    "the service-account key at '%s' was rejected by Google.",
    "Common causes: the key was revoked or deleted, the service account is disabled,",
    "or this host's clock has drifted - service-account auth is JWT-signed and clock-sensitive.",
    sep = "\n"), gac)
}

#' Fetch an Application Default Credentials token for Secret Manager
#'
#' @return A gargle token.
#' @noRd
secretsR_token <- function() {
  # ---- start ---- #
  cached <- secret_cache_get(".token")
  if (!is.null(cached) && !secretsR_token_stale()) return(cached)

  if (!is.null(cached) && inherits(cached, "Token2.0")) {
    refreshed <- tryCatch({ cached$refresh(); TRUE }, error = function(e) {
      # Never swallow this. A revoked key, clock skew or a network blip would
      # otherwise leave a STALE bearer in play, surfacing later as a 401
      # attributed to the wrong cause.
      secretsR_warn(sprintf("token refresh failed (%s); re-authenticating",
                            conditionMessage(e)))
      FALSE
    })
    if (refreshed) {
      secret_cache_set(".token_minted_at", Sys.time())
      return(cached)
    }
    secret_cache_set(".token", NULL)
  }

  # Scoped to this call only. A session-global cred_funs_set() would change
  # behaviour for bigrquery/googlesheets4 running in the same process.
  gargle::local_cred_funs(funs = secretsR_cred_funs(), action = "replace")

  # gargle/httr use curl's default 300s connect timeout. In a container whose
  # egress is DROPped rather than REJECTed, an unbounded token fetch hangs for
  # minutes - the same hang-instead-of-crash failure the pruned credential chain
  # exists to prevent, one layer down.
  token <- httr::with_config(
    httr::timeout(15),
    gargle_token_fetch(scopes = SECRETSR_SCOPE)
  )
  if (is.null(token)) stop(secretsR_no_credentials_message(), call. = FALSE)

  secret_cache_set(".token", token)
  secret_cache_set(".token_minted_at", Sys.time())
  token
}

#' Extract the bearer string from a gargle token
#'
#' Separate because gargle's credential classes nest differently. Verified
#' 2026-08-18 against both an authorized_user ADC (Gargle2.0) and a
#' service-account key (TokenServiceAccount): both populate
#' credentials$access_token, so the first branch is the one that applies in
#' practice. The second is a defensive fallback for types not yet encountered.
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
#' @return Secret value as a character scalar. UTF-8 validation and labelling
#'   happen centrally in secret_get(), so all three backends share one rule.
#' @noRd
secret_get_gsm <- function(name, version = "latest") {
  # ---- start ---- #
  project <- secretsR_project()
  url <- sprintf(
    "https://secretmanager.googleapis.com/v1/projects/%s/secrets/%s/versions/%s:access",
    project,
    utils::URLencode(name, reserved = TRUE),
    utils::URLencode(as.character(version), reserved = TRUE)
  )
  req <- httr2::request(url)
  req <- httr2::req_auth_bearer_token(req, secretsR_access_token(secretsR_token()))
  # Bounded so a stalled TLS connection crashes rather than hangs.
  req <- httr2::req_timeout(req, seconds = 10)
  # httr2's default is_transient covers 429/503, which is exactly spec 5.10.
  # max_seconds bounds the whole retry budget: R is single-threaded, so an
  # unbounded retry inside a Shiny app stalls every session, not just this one.
  req <- httr2::req_retry(req, max_tries = 3, max_seconds = 20)

  body <- tryCatch(
    gsm_perform(req),
    httr2_http_401 = function(e) {
      secret_cache_set(".token", NULL)
      secret_cache_set(".token_minted_at", NULL)
      stop(sprintf("GSM: authentication rejected for '%s'. The cached token has been discarded; the next call will re-authenticate.",
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
  rawToChar(jsonlite::base64_dec(data))
}
