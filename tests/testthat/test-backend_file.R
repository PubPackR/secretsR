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
