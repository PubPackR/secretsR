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

test_that("the file backend receives the supplied key", {
  secret_cache_clear(); seen <- NULL
  local_mocked_bindings(
    secret_get_file = function(name, file_key) { seen <<- file_key; "v" },
    secretsR_production_marker = function() "/nonexistent"
  )
  withr::with_envvar(c(SF_SECRET_BACKEND = "file"),
                     secret_get("studyflix-billomat-api-key", file_key = "master-pw"))
  expect_equal(seen, "master-pw")
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

# ---- the file: namespace must stay reachable on the default backend ----

test_that("a file-backend-internal name resolves through secret_get()", {
  # The legacy map defines two of these. Validating names against
  # ^[A-Za-z0-9_-]+$ made the postgres credential unreachable on the DEFAULT
  # backend - secret_get() rejected the colon its own map depends on.
  secret_cache_clear()
  local_mocked_bindings(secret_get_file = function(name, file_key) "pg-value",
                        secretsR_is_production = function() FALSE)
  withr::with_envvar(c(SF_SECRET_BACKEND = "file"),
                     expect_equal(secret_get("file:postgresql-credentials", file_key = "pw"),
                                  "pg-value"))
})

test_that("a genuinely malformed name is still refused", {
  expect_error(secret_get("studyflix/../other"), "not a valid secret name")
  expect_error(secret_get("file:bad/name"), "not a valid secret name")
})

# ---- versions exist only in Secret Manager ----

test_that("a pinned version is refused on a backend that has none", {
  secret_cache_clear()
  local_mocked_bindings(secret_get_env = function(name) "from-env",
                        secret_get_file = function(name, file_key) "from-file",
                        secretsR_is_production = function() FALSE)
  withr::with_envvar(c(SF_SECRET_BACKEND = "env"),
                     expect_error(secret_get("studyflix-test", version = "3"),
                                  "only Secret Manager has versions"))
  withr::with_envvar(c(SF_SECRET_BACKEND = "file"),
                     expect_error(secret_get("studyflix-test", version = "3"),
                                  "cannot honour version"))
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
