#' Map a secret name to its environment variable name
#'
#' Upper-case, hyphens to underscores, prefixed (spec 5.1).
#'
#' @param name Secret name.
#' @return Environment variable name.
#' @noRd
secret_env_var <- function(name) {
  # ---- start ---- #
  paste0("SF_SECRET_", toupper(gsub("-", "_", name, fixed = TRUE)))
}

#' Read a secret from the environment
#'
#' Break-glass and unit-test backend only. Not a deployment mechanism.
#'
#' An empty value is treated as missing: a credential that silently becomes ""
#' fails far from its cause.
#'
#' @param name Secret name.
#' @return Secret value as a character scalar.
#' @noRd
secret_get_env <- function(name) {
  # ---- start ---- #
  var <- secret_env_var(name)
  value <- Sys.getenv(var, unset = NA_character_)
  if (is.na(value) || !nzchar(value)) {
    stop(sprintf("env backend: %s is not set or is empty", var), call. = FALSE)
  }
  value
}
