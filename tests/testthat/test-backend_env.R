test_that("the name transform matches the spec example", {
  expect_equal(secret_env_var("studyflix-postgresql-connection"),
               "SF_SECRET_STUDYFLIX_POSTGRESQL_CONNECTION")
})

test_that("the env backend returns the value", {
  withr::with_envvar(c(SF_SECRET_STUDYFLIX_TEST = "abc123"),
                     expect_equal(secret_get_env("studyflix-test"), "abc123"))
})

test_that("a missing env var errors and names the variable", {
  withr::with_envvar(c(SF_SECRET_STUDYFLIX_TEST = NA),
                     expect_error(secret_get_env("studyflix-test"), "SF_SECRET_STUDYFLIX_TEST"))
})

test_that("an empty env var is treated as missing, not as an empty secret", {
  withr::with_envvar(c(SF_SECRET_STUDYFLIX_TEST = ""),
                     expect_error(secret_get_env("studyflix-test")))
})

test_that("the error names the variable, not its value", {
  withr::with_envvar(c(SF_SECRET_STUDYFLIX_TEST = "abc123"), {
    msg <- tryCatch(secret_get_env("studyflix-nonexistent"), error = conditionMessage)
    expect_match(msg, "SF_SECRET_STUDYFLIX_NONEXISTENT")
    expect_false(grepl("abc123", msg, fixed = TRUE))
  })
})
