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
