fake_token <- function() {
  structure(list(credentials = list(access_token = "fake-token")), class = "TestToken")
}

# secretsR_token() memoises into the same cache. Without clearing, the first
# test populates .token and every later test gets a cache hit, its mock never
# fires, and its assertion passes vacuously or errors on NULL.

test_that("the token request uses exactly the cloud-platform scope", {
  secret_cache_clear()
  captured <- NULL
  local_mocked_bindings(
    gargle_token_fetch = function(scopes, ...) { captured <<- scopes; fake_token() }
  )
  secretsR_token()
  expect_equal(captured, "https://www.googleapis.com/auth/cloud-platform")
})

test_that("the live registry is pruned to app_default and gce during the call", {
  secret_cache_clear()
  seen <- NULL
  local_mocked_bindings(
    gargle_token_fetch = function(scopes, ...) {
      seen <<- names(gargle::cred_funs_list())   # the REAL registry, mid-call
      fake_token()
    }
  )
  secretsR_token()
  expect_setequal(seen, c("credentials_app_default", "credentials_gce"))
  expect_false("credentials_user_oauth2" %in% seen)
})

test_that("the registry is restored to the DEFAULT chain after the call", {
  secret_cache_clear()
  # Reset to a known-good starting point. Without this the test reads whatever
  # an earlier block left behind - and if the implementation used a global
  # cred_funs_set(), that is already the pruned list, so the assertion would
  # compare pruned to pruned and pass while the registry leaked permanently.
  gargle::cred_funs_set(gargle::cred_funs_list_default())
  before <- names(gargle::cred_funs_list())

  local_mocked_bindings(gargle_token_fetch = function(scopes, ...) fake_token())
  secretsR_token()

  expect_equal(names(gargle::cred_funs_list()), before)
  # Asserted positively: a leaked prune would remove exactly this one.
  expect_true("credentials_user_oauth2" %in% names(gargle::cred_funs_list()))
})

test_that("the registry is restored even when the token fetch errors", {
  secret_cache_clear()
  gargle::cred_funs_set(gargle::cred_funs_list_default())
  before <- names(gargle::cred_funs_list())

  local_mocked_bindings(gargle_token_fetch = function(scopes, ...) stop("boom"))
  expect_error(secretsR_token(), "boom")

  expect_equal(names(gargle::cred_funs_list()), before)
  expect_true("credentials_user_oauth2" %in% names(gargle::cred_funs_list()))
})

test_that("no credentials produces an actionable crash", {
  secret_cache_clear()
  local_mocked_bindings(gargle_token_fetch = function(scopes, ...) NULL)
  expect_error(secretsR_token(), "application-default login")
})

test_that("the access token is extracted from the gargle credential", {
  secret_cache_clear()
  expect_equal(secretsR_access_token(fake_token()), "fake-token")
  expect_error(secretsR_access_token(structure(list(), class = "TestToken")),
               "could not extract")
})
