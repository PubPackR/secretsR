skip_unless_integration <- function() {
  skip_if_not(nzchar(Sys.getenv("SECRETSR_INTEGRATION")),
              "set SECRETSR_INTEGRATION=1 to run")
}

test_that("a real secret round-trips through GSM", {
  skip_unless_integration(); secret_cache_clear()
  # Pinned to version 1 so this stays true both before and after the disabled
  # version is added below. Reading "latest" here would make the two tests
  # mutually exclusive.
  withr::with_envvar(c(SF_SECRET_BACKEND = "gsm", SF_GSM_PROJECT = "studyflix-secrets"),
    expect_equal(secret_get("secretsr-integration-test", version = "1"), "round-trip-ok"))
})

test_that("latest fails when the newest version is disabled, and a pin still works", {
  skip_unless_integration(); secret_cache_clear()
  withr::with_envvar(c(SF_SECRET_BACKEND = "gsm", SF_GSM_PROJECT = "studyflix-secrets"), {
    expect_error(secret_get("secretsr-integration-test"), "pin an explicit version")
    secret_cache_clear()
    expect_equal(secret_get("secretsr-integration-test", version = "1"), "round-trip-ok")
  })
})
