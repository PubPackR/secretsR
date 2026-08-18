test_that("backend defaults to file when unset", {
  withr::with_envvar(c(SF_SECRET_BACKEND = NA), expect_equal(secretsR_backend(), "file"))
})

test_that("backend reads the environment variable", {
  withr::with_envvar(c(SF_SECRET_BACKEND = "gsm"), expect_equal(secretsR_backend(), "gsm"))
})

test_that("an unknown backend is rejected loudly", {
  withr::with_envvar(c(SF_SECRET_BACKEND = "s3"), expect_error(secretsR_backend(), "SF_SECRET_BACKEND"))
})

test_that("an empty backend variable falls back to the default", {
  withr::with_envvar(c(SF_SECRET_BACKEND = ""), expect_equal(secretsR_backend(), "file"))
})

test_that("project defaults, and honours an explicit value", {
  withr::with_envvar(c(SF_GSM_PROJECT = NA), expect_equal(secretsR_project(), "studyflix-secrets"))
  withr::with_envvar(c(SF_GSM_PROJECT = "other-proj"), expect_equal(secretsR_project(), "other-proj"))
})

test_that("an empty project variable falls back to the default", {
  withr::with_envvar(c(SF_GSM_PROJECT = ""), expect_equal(secretsR_project(), "studyflix-secrets"))
})
