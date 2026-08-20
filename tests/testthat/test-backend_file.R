make_encrypted <- function(dir, value, key) {
  p <- file.path(dir, "secret.txt")
  writeLines(safer::encrypt_string(value, key = key), p)
  p
}

test_that("the file backend round-trips a safer-encrypted string", {
  tmp <- withr::local_tempdir()
  p <- make_encrypted(tmp, "hunter2", "master-pw")
  local_mocked_bindings(secret_legacy_path = function(name) p)
  expect_equal(secret_get_file("studyflix-billomat-api-key", "master-pw"), "hunter2")
})

test_that("a wrong key errors rather than returning garbage", {
  tmp <- withr::local_tempdir()
  p <- make_encrypted(tmp, "hunter2", "master-pw")
  local_mocked_bindings(secret_legacy_path = function(name) p)
  expect_error(secret_get_file("studyflix-billomat-api-key", "wrong-pw"), "could not decrypt")
})

test_that("the decryption error does not leak the plaintext", {
  tmp <- withr::local_tempdir()
  p <- make_encrypted(tmp, "hunter2", "master-pw")
  local_mocked_bindings(secret_legacy_path = function(name) p)
  msg <- tryCatch(secret_get_file("studyflix-billomat-api-key", "wrong-pw"),
                  error = conditionMessage)
  expect_false(grepl("hunter2", msg, fixed = TRUE))
})

test_that("a missing file errors and names the path", {
  local_mocked_bindings(secret_legacy_path = function(name) "does/not/exist.txt")
  expect_error(secret_get_file("studyflix-billomat-api-key", "k"), "does/not/exist.txt")
})

test_that("a missing key errors before touching the filesystem", {
  expect_error(secret_get_file("studyflix-billomat-api-key", ""), "SF_SECRET_FILE_KEY")
})

# ---- previously outstanding: the SF_SECRET_FILE_KEY default was never exercised ----

test_that("the key falls back to SF_SECRET_FILE_KEY when none is passed", {
  # Every other test passes the key positionally, so the default argument -
  # the path Billomatics relies on - had never run.
  tmp <- withr::local_tempdir()
  p <- file.path(tmp, "secret.txt")
  writeLines(safer::encrypt_string("hunter2", key = "master-pw"), p)
  local_mocked_bindings(secret_legacy_path = function(name) p)
  withr::with_envvar(c(SF_SECRET_FILE_KEY = "master-pw"),
                     expect_equal(secret_get_file("studyflix-billomat-api-key"), "hunter2"))
})

test_that("an empty file is reported as empty, not as a wrong key", {
  # The master password is shared across every keys/ file: a wrong key fails
  # every secret in the process, so a single failing path points at the file.
  tmp <- withr::local_tempdir()
  p <- file.path(tmp, "empty.txt")
  file.create(p)
  local_mocked_bindings(secret_legacy_path = function(name) p)
  expect_error(secret_get_file("studyflix-billomat-api-key", "master-pw"),
               "empty or unreadable")
})

test_that("a trailing blank line is still tolerated", {
  tmp <- withr::local_tempdir()
  p <- file.path(tmp, "secret.txt")
  writeLines(c(safer::encrypt_string("hunter2", key = "master-pw"), ""), p)
  local_mocked_bindings(secret_legacy_path = function(name) p)
  expect_equal(secret_get_file("studyflix-billomat-api-key", "master-pw"), "hunter2")
})

test_that("the damaged-file cause is named ahead of the shared key", {
  tmp <- withr::local_tempdir()
  p <- file.path(tmp, "damaged.txt")
  writeLines("this-is-not-safer-output", p)
  local_mocked_bindings(secret_legacy_path = function(name) p)
  msg <- tryCatch(secret_get_file("studyflix-billomat-api-key", "master-pw"),
                  error = conditionMessage)
  expect_match(msg, "damaged or not safer-encrypted")
  expect_lt(regexpr("damaged", msg), regexpr("key is wrong", msg))
})
