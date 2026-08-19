test_that("known secrets map to their legacy paths", {
  expect_equal(secret_legacy_path("studyflix-billomat-api-key"), "../../keys/billomat.txt")
  expect_equal(secret_legacy_path("studyflix-msgraph-delegated-storekey"),
               "../../keys/Microsoft365R/msgraph_delegated_storekey.txt")
})

test_that("an unknown secret name errors loudly", {
  expect_error(secret_legacy_path("studyflix-google-sheets"), "unknown secret name")
})

test_that("the legacy data key is not resolvable as a file", {
  expect_error(secret_legacy_path("studyflix-legacy-data-key"), "unknown secret name")
})

test_that("every mapped path is unique", {
  paths <- unlist(secretsR_legacy_map, use.names = FALSE)
  expect_equal(length(paths), length(unique(paths)))
})

test_that("keys are either canonical studyflix- names or explicitly file-internal", {
  expect_true(all(grepl("^(studyflix-|file:)", names(secretsR_legacy_map))))
})

test_that("a GSM-only name says what to use instead of reporting a typo", {
  msg <- tryCatch(secret_legacy_path("studyflix-postgresql-connection"),
                  error = conditionMessage)
  expect_match(msg, "no legacy file")
  expect_match(msg, "file:postgresql-credentials", fixed = TRUE)
})

test_that("a genuine typo still reports as an unknown name", {
  expect_error(secret_legacy_path("studyflix-postgres-connection"), "unknown secret name")
})
