fake_token <- function() {
  structure(list(credentials = list(access_token = "fake-token")), class = "TestToken")
}
ok_body <- function(x = "hunter2") {
  list(payload = list(data = jsonlite::base64_enc(charToRaw(x))))
}
http_err <- function(status) {
  stop(structure(list(message = paste("HTTP", status)),
                 class = c(paste0("httr2_http_", status), "httr2_http", "error", "condition")))
}

test_that("the payload is base64-decoded", {
  local_mocked_bindings(secretsR_token = fake_token, gsm_perform = function(req) ok_body())
  expect_equal(secret_get_gsm("studyflix-test"), "hunter2")
})

test_that("the bearer token reaches the request", {
  seen <- NULL
  local_mocked_bindings(
    secretsR_token = fake_token,
    gsm_perform = function(req) {
      # httr2 >= 1.2 stores redacted headers as weakrefs; req$headers$Authorization
      # is not coercible to character.
      seen <<- httr2::req_get_headers(req, redact = "reveal")$Authorization
      ok_body()
    }
  )
  secret_get_gsm("studyflix-test")
  expect_equal(seen, "Bearer fake-token")
})

test_that("the request URL pins the requested version", {
  seen <- NULL
  local_mocked_bindings(
    secretsR_token = fake_token,
    gsm_perform = function(req) { seen <<- req$url; ok_body("x") }
  )
  secret_get_gsm("studyflix-test", version = "3")
  expect_match(seen, "/versions/3:access$")
})

test_that("a 403 explains which permission is missing", {
  local_mocked_bindings(secretsR_token = fake_token, gsm_perform = function(req) http_err(403))
  expect_error(secret_get_gsm("studyflix-test"), "secretAccessor")
})

test_that("a 404 names the secret and project", {
  local_mocked_bindings(secretsR_token = fake_token, gsm_perform = function(req) http_err(404))
  expect_error(secret_get_gsm("studyflix-nope"), "studyflix-nope")
})

test_that("a 400 tells the caller to pin an explicit version", {
  local_mocked_bindings(secretsR_token = fake_token, gsm_perform = function(req) http_err(400))
  expect_error(secret_get_gsm("studyflix-test"), "pin an explicit version")
})

test_that("other HTTP errors propagate rather than being swallowed", {
  local_mocked_bindings(secretsR_token = fake_token, gsm_perform = function(req) http_err(500))
  expect_error(secret_get_gsm("studyflix-test"), "HTTP 500")
})

test_that("an unexpected response shape errors clearly", {
  local_mocked_bindings(secretsR_token = fake_token,
                        gsm_perform = function(req) list(payload = list()))
  expect_error(secret_get_gsm("studyflix-test"), "unexpected response shape")
})
