test_that("known secrets map to their legacy paths", {
  expect_equal(secret_legacy_path("studyflix-billomat-api-key"), "../../keys/billomat.txt")
  expect_equal(secret_legacy_path("studyflix-msgraph-delegated-storekey"),
               "../../keys/Microsoft365R/msgraph_delegated_storekey.txt")
})

test_that("an unknown secret name errors loudly", {
  expect_error(secret_legacy_path("studyflix-google-sheets"), "unknown secret name")
})

test_that("neither legacy data key is resolvable as a file", {
  # There are two, not one: base-02 encrypts its output under the Asana password
  # while ~49 other sites use the Billomat one, and design 3.3 establishes those
  # are different strings. Neither is the contents of any keys/ file - each IS
  # the password such files are encrypted with - so both must stay unmapped.
  expect_error(secret_legacy_path("studyflix-legacy-data-key-billomat"),
               "unknown secret name")
  expect_error(secret_legacy_path("studyflix-legacy-data-key-asana"),
               "unknown secret name")
})

test_that("the map covers every service authentication_process dispatches", {
  # msgraph_sharepoint landed in Billomatics PR #32 on 2026-08-19, after this map
  # was last verified against the real tree. gemini was excluded as unused, but
  # authentication_process() still dispatches it, so it has to resolve or the
  # equivalence test in design 5.5 fails on it. Its key file does exist on the
  # server (78 bytes, verified 2026-08-20) - unused, not broken.
  expect_equal(secret_legacy_path("studyflix-msgraph-sharepoint-config"),
               "../../keys/Microsoft365R/msgraph_sharepoint.txt")
  expect_equal(secret_legacy_path("studyflix-gemini-api-key"),
               "../../keys/gemini_key.txt")
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
