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

test_that("secret_backend() reports the resolved backend", {
  withr::with_envvar(c(SF_SECRET_BACKEND = "file"), expect_identical(secret_backend(), "file"))
  withr::with_envvar(c(SF_SECRET_BACKEND = "env"), expect_identical(secret_backend(), "env"))
  withr::with_envvar(c(SF_SECRET_BACKEND = "gsm"), expect_identical(secret_backend(), "gsm"))
})

test_that("secret_backend() defaults to file and rejects an unknown value", {
  # It is the same resolution secret_get() uses, deliberately: a consumer that
  # branches on the backend must not be able to disagree with the dispatcher
  # about what the backend is.
  withr::with_envvar(c(SF_SECRET_BACKEND = NA), expect_identical(secret_backend(), "file"))
  withr::with_envvar(c(SF_SECRET_BACKEND = "s3"), expect_error(secret_backend(), "SF_SECRET_BACKEND"))
})

test_that("secret_backend() is exported", {
  # Consumers reaching secretsR::: is how the resolution rules drift out of sync.
  expect_true("secret_backend" %in% getNamespaceExports("secretsR"))
})
