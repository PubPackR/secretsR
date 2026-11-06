test_that("dispatch follows SF_SECRET_BACKEND", {
  secret_cache_clear()
  local_mocked_bindings(secret_get_env = function(name) "from-env",
                        secretsR_production_marker = function() "/nonexistent")
  withr::with_envvar(c(SF_SECRET_BACKEND = "env"),
                     expect_equal(secret_get("studyflix-test"), "from-env"))
})

test_that("a second call inside the process does not re-fetch", {
  secret_cache_clear(); calls <- 0
  local_mocked_bindings(secret_get_env = function(name) { calls <<- calls + 1; "v" },
                        secretsR_production_marker = function() "/nonexistent")
  withr::with_envvar(c(SF_SECRET_BACKEND = "env"), {
    secret_get("studyflix-test"); secret_get("studyflix-test")
  })
  expect_equal(calls, 1)
})

test_that("different versions are cached separately", {
  secret_cache_clear(); calls <- 0
  local_mocked_bindings(
    secret_get_gsm = function(name, version) { calls <<- calls + 1; paste0("v", version) },
    secretsR_production_marker = function() "/nonexistent"
  )
  withr::with_envvar(c(SF_SECRET_BACKEND = "gsm"), {
    expect_equal(secret_get("s", version = "1"), "v1")
    expect_equal(secret_get("s", version = "2"), "v2")
    expect_equal(secret_get("s", version = "1"), "v1")   # cache hit, not a third fetch
  })
  expect_equal(calls, 2)
})

test_that("an unset backend dispatches to Secret Manager", {
  secret_cache_clear()
  local_mocked_bindings(secret_get_gsm = function(name, version) "from-gsm",
                        secretsR_production_marker = function() "/nonexistent")
  withr::with_envvar(c(SF_SECRET_BACKEND = NA),
                     expect_equal(secret_get("studyflix-test"), "from-gsm"))
})

test_that("a file_key is refused before any backend is asked, on every backend", {
  # Billomatics passes file_key on its non-gsm branch. Accepting and ignoring it
  # would hide that the branch is dead; the message must name the removal.
  secret_cache_clear(); calls <- 0L
  local_mocked_bindings(
    secret_get_gsm = function(name, version) { calls <<- calls + 1L; "v" },
    secret_get_env = function(name) { calls <<- calls + 1L; "v" },
    secretsR_production_marker = function() "/nonexistent"
  )
  for (b in c("gsm", "env")) {
    withr::with_envvar(c(SF_SECRET_BACKEND = b),
                       expect_error(secret_get("studyflix-billomat-api-key", file_key = "master-pw"),
                                    "removed"))
  }
  expect_identical(calls, 0L)
})

test_that("file_key = NULL is still accepted", {
  secret_cache_clear()
  local_mocked_bindings(secret_get_gsm = function(name, version) "ok",
                        secretsR_production_marker = function() "/nonexistent")
  withr::with_envvar(c(SF_SECRET_BACKEND = "gsm"),
                     expect_equal(secret_get("studyflix-test", file_key = NULL), "ok"))
})

test_that("a production host refuses non-gsm backends", {
  secret_cache_clear()
  tmp <- withr::local_tempdir(); marker <- file.path(tmp, "production"); file.create(marker)
  local_mocked_bindings(secretsR_production_marker = function() marker)
  withr::with_envvar(c(SF_SECRET_BACKEND = "env"),
                     expect_error(secret_get("studyflix-test"), "production"))
})

test_that("a production host still permits gsm", {
  secret_cache_clear()
  tmp <- withr::local_tempdir(); marker <- file.path(tmp, "production"); file.create(marker)
  local_mocked_bindings(secretsR_production_marker = function() marker,
                        secret_get_gsm = function(name, version) "ok")
  withr::with_envvar(c(SF_SECRET_BACKEND = "gsm"),
                     expect_equal(secret_get("studyflix-test"), "ok"))
})

test_that("a non-character name is rejected", {
  expect_error(secret_get(42), "character")
})

test_that("a non-ASCII payload is labelled UTF-8 by the dispatcher", {
  secret_cache_clear()
  local_mocked_bindings(secret_get_gsm = function(name, version) "Grüße",
                        secretsR_is_production = function() FALSE)
  withr::with_envvar(c(SF_SECRET_BACKEND = "gsm"), {
    out <- secret_get("studyflix-test")
    expect_equal(Encoding(out), "UTF-8")
    expect_equal(out, "Grüße")
  })
})

test_that("a non-UTF-8 payload is rejected, whichever backend produced it", {
  secret_cache_clear()
  bad <- rawToChar(as.raw(c(0xff, 0xfe, 0x41)))
  local_mocked_bindings(secret_get_gsm = function(name, version) bad,
                        secretsR_is_production = function() FALSE)
  withr::with_envvar(c(SF_SECRET_BACKEND = "gsm"),
                     expect_error(secret_get("studyflix-test"), "not valid UTF-8"))
})

test_that("an empty or NA value from any backend is rejected", {
  secret_cache_clear()
  local_mocked_bindings(secretsR_is_production = function() FALSE)
  for (bad in list("", NA_character_, character(0), c("a", "b"))) {
    local_mocked_bindings(secret_get_gsm = function(name, version) bad)
    withr::with_envvar(c(SF_SECRET_BACKEND = "gsm"), {
      secret_cache_clear()
      expect_error(secret_get("studyflix-test"), "no usable value")
    })
  }
})

test_that("an unsafe secret name is rejected before any network call", {
  expect_error(secret_get("../../other/secrets/evil"), "not a valid secret name")
})

test_that("a malformed name is refused, including the old file: namespace", {
  # The "file:" prefix was the file backend's own namespace. With the backend
  # gone it is an ordinary invalid name, refused before any network call.
  expect_error(secret_get("studyflix/../other"), "not a valid secret name")
  expect_error(secret_get("file:bad/name"), "not a valid secret name")
  expect_error(secret_get("file:postgresql-credentials"), "not a valid secret name")
})

# ---- versions exist only in Secret Manager ----

test_that("a pinned version is refused on a backend that has none", {
  secret_cache_clear()
  local_mocked_bindings(secret_get_env = function(name) "from-env",
                        secretsR_is_production = function() FALSE)
  withr::with_envvar(c(SF_SECRET_BACKEND = "env"),
                     expect_error(secret_get("studyflix-test", version = "3"),
                                  "only Secret Manager has versions"))
})

test_that("latest is still accepted on every backend", {
  secret_cache_clear()
  local_mocked_bindings(secret_get_env = function(name) "from-env",
                        secretsR_is_production = function() FALSE)
  withr::with_envvar(c(SF_SECRET_BACKEND = "env"),
                     expect_equal(secret_get("studyflix-test", version = "latest"), "from-env"))
})

# ---- previously outstanding: the spec 5.2 WARN was unasserted ----

test_that("a non-gsm backend warns once per process, not once per call", {
  secret_cache_clear()
  local_mocked_bindings(secret_get_env = function(name) "from-env",
                        secretsR_is_production = function() FALSE)
  # log4r's default console appender writes to stdout, so the WARN lands in the
  # output stream, not the message stream. (Without log4r installed,
  # secretsR_warn() degrades to warning(), which goes to stderr instead - the
  # two paths do not agree on a stream.)
  msgs <- withr::with_envvar(c(SF_SECRET_BACKEND = "env"), {
    capture.output(for (i in 1:5) secret_get(paste0("studyflix-test-", i)), type = "output")
  })
  expect_length(grep("non-gsm backend", msgs), 1)
})

test_that("the gsm backend does not warn at all", {
  secret_cache_clear()
  local_mocked_bindings(secret_get_gsm = function(name, version) "ok",
                        secretsR_is_production = function() FALSE)
  msgs <- withr::with_envvar(c(SF_SECRET_BACKEND = "gsm"), {
    capture.output(secret_get("studyflix-test"), type = "output")
  })
  expect_length(grep("non-gsm backend", msgs), 0)
})

test_that("gsm lookups are not invalidated by a change of working directory", {
  # cwd is not part of the cache key: it changes nothing for gsm, and including
  # it would turn a directory change into a needless API call on every lookup.
  secret_cache_clear()
  withr::local_envvar(c(SF_SECRET_BACKEND = "gsm", SF_GSM_PROJECT = "p"))
  calls <- 0L
  local_mocked_bindings(
    secret_get_gsm = function(name, version = "latest") { calls <<- calls + 1L; "v" }
  )
  d <- withr::local_tempdir()
  expect_identical(secret_get("studyflix-crm-api-key"), "v")
  withr::with_dir(d, expect_identical(secret_get("studyflix-crm-api-key"), "v"))
  expect_identical(calls, 1L)
})
