#' Read a secret from the legacy safer-encrypted keys/ folder
#'
#' Transition and rollback path only. Deleted in Plan F.
#'
#' @param name Secret name.
#' @param file_key The safer master password. Defaults to SF_SECRET_FILE_KEY.
#' @return Secret value as a character scalar.
#' @noRd
secret_get_file <- function(name, file_key = Sys.getenv("SF_SECRET_FILE_KEY")) {
  # ---- start ---- #
  if (!nzchar(file_key)) {
    stop("file backend: no decryption key supplied and SF_SECRET_FILE_KEY is unset",
         call. = FALSE)
  }
  path <- secret_legacy_path(name)
  if (!file.exists(path)) {
    stop(sprintf("file backend: %s not found (cwd: %s)", path, getwd()), call. = FALSE)
  }
  # readLines() can return length > 1 if a legacy file has a trailing blank
  # line; decrypt_string() expects a scalar.
  payload <- readLines(path, warn = FALSE)[1]
  tryCatch(
    safer::decrypt_string(payload, key = file_key),
    error = function(e) {
      # Replaces safer's fixed message, which does not name the file. Note this
      # also masks a truncated or non-safer file, which reports as "wrong key".
      stop(sprintf("file backend: could not decrypt %s - wrong key, or the file is not safer-encrypted",
                   path), call. = FALSE)
    }
  )
}
