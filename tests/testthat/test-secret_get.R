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
