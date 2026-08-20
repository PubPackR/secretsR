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
  if (!is.character(file_key) || length(file_key) != 1L || is.na(file_key) || !nzchar(file_key)) {
    stop("file backend: no decryption key supplied and SF_SECRET_FILE_KEY is unset",
         call. = FALSE)
  }
  path <- secret_legacy_path(name)
  if (!file.exists(path)) {
    stop(sprintf("file backend: %s not found (cwd: %s)", path, getwd()), call. = FALSE)
  }
  # readLines() can return length > 1 if a legacy file has a trailing blank
  # line; decrypt_string() expects a scalar. Taking [1] is deliberate tolerance
  # for that, not an oversight.
  lines <- readLines(path, warn = FALSE)
  # An empty or blank first line fails inside decrypt_string() and would be
  # rewritten below as "wrong key" - pointing at the shared master password
  # instead of at the one damaged file that is actually the problem.
  if (length(lines) < 1L || is.na(lines[1]) || !nzchar(lines[1])) {
    stop(sprintf("file backend: %s is empty or unreadable", path), call. = FALSE)
  }
  payload <- lines[1]
  tryCatch(
    safer::decrypt_string(payload, key = file_key),
    error = function(e) {
      # Replaces safer's fixed message, which does not name the file. The file is
      # named as the likelier cause because the master password is shared across
      # every keys/ file: a wrong key fails every secret in the process, not just
      # this one, so a single failing path points at the file.
      stop(sprintf("file backend: could not decrypt %s - the file is damaged or not safer-encrypted, or the key is wrong",
                   path), call. = FALSE)
    }
  )
}
