#' Legacy keys/ paths by secret name
#'
#' Bridges the file backend, which needs a path, to secret_get(), which takes a
#' name. Entries prefixed "file:" are file-backend-internal identifiers, not GSM
#' secret names - the two postgres files collapse into the single GSM secret
#' studyflix-postgresql-connection (spec 5.8). Deleted with the file backend in
#' Plan F.
#'
#' Deliberately absent:
#'   - studyflix-legacy-data-key: not the contents of any file. It is the
#'     data-encryption key for base-data/ RDS files and the shinymanager SQLite
#'     stores (spec 3.3, 5.6). Today it is the same string as the keys/ master
#'     password that decrypts billomat.txt; the two roles are named separately so
#'     Plan G can re-key the data and let them diverge. Under this backend it IS
#'     the file_key parameter.
#'   - gemini: requested by zero repositories (IAM matrix). Verify, then drop -
#'     do not carry a dead credential into GSM.
#'   - the four service-account-JSON services: they decrypt whole files rather
#'     than strings, handled inside Billomatics (spec 5.7, Plan C2).
#'
#' @noRd
secretsR_legacy_map <- list(
  "studyflix-billomat-api-key"           = "../../keys/billomat.txt",
  "studyflix-crm-api-key"                = "../../keys/CRM.txt",
  "studyflix-crm-lm-api-key"             = "../../keys/CRM_LM.txt",
  "studyflix-asana-token"                = "../../keys/asana.txt",
  "studyflix-msgraph-secret"             = "../../keys/Microsoft365R/microsoft365r.txt",
  "studyflix-msgraph-scoped-app-secret"  = "../../keys/Microsoft365R/msgraph_scoped_app.txt",
  "studyflix-msgraph-delegated-secret"   = "../../keys/Microsoft365R/msgraph_delegated_secret.txt",
  "studyflix-msgraph-delegated-storekey" = "../../keys/Microsoft365R/msgraph_delegated_storekey.txt",
  "studyflix-brevo-smtp-key"             = "../../keys/Brevo/smpt-key.txt",
  "studyflix-bonusdb-key"                = "../../keys/BonusDB/bonusDBKey.txt",
  "studyflix-cleverreach-token"          = "../../keys/cleverReach_key.txt",
  "studyflix-openrouter-api-key"         = "../../keys/openrouter.txt",
  "studyflix-openai-admin-api-key"       = "../../keys/openai_admin.txt",
  "studyflix-github-token"               = "../../keys/Github/github_token.txt",
  "studyflix-metabase-api-key"           = "../../keys/metabase.txt",
  "studyflix-personio-client-id"         = "../../keys/Personio/personio_client_id.txt",
  "studyflix-personio-client-secret"     = "../../keys/Personio/personio_client_secret.txt",
  "file:postgresql-credentials"          = "../../keys/PostgreSQL_DB/postgresql_key.txt",
  "file:postgresql-server"               = "../../keys/PostgreSQL_DB/postgresql_server.txt"
)

#' Resolve a secret name to its legacy file path
#'
#' Errors on an unknown name rather than returning NA. authentication_process()
#' currently falls through to keys[[service]] <- NA for unrecognised names, which
#' silently disables authentication - via a typo, or via version skew between the
#' installed Billomatics and the code being called (spec 3.5). This is the
#' regression guard for that defect class.
#'
#' @param name Secret name.
#' @return Relative path to the encrypted legacy file.
#' @noRd
secret_legacy_path <- function(name) {
  # ---- start ---- #
  if (!name %in% names(secretsR_legacy_map)) {
    hint <- secretsR_gsm_only[[name]]
    if (!is.null(hint)) {
      stop(sprintf("file backend: '%s' has no legacy file - %s", name, hint), call. = FALSE)
    }
    stop(sprintf("unknown secret name: '%s'", name), call. = FALSE)
  }
  secretsR_legacy_map[[name]]
}

#' Canonical names that exist in Secret Manager but have no single legacy file
#'
#' These do not resolve on the file backend, so flipping SF_SECRET_BACKEND back
#' is not transparent for them. Naming them turns "unknown secret name" into a
#' message that says what to use instead - the alternative is an operator
#' mid-rollback hunting for a typo in a name that is not a typo.
#'
#' This maps the gap; it does not close it. Composing the two postgres halves
#' into the single payload GSM stores would mean inventing that payload's format
#' here, which belongs in the migration plan (spec 5.8).
#'
#' @noRd
secretsR_gsm_only <- list(
  "studyflix-postgresql-connection" = paste(
    "the file backend keeps this split across 'file:postgresql-credentials' and",
    "'file:postgresql-server' (spec 5.8), which Billomatics composes;",
    "there is no single legacy file for it"
  )
)
