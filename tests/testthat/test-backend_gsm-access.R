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

# ---- previously outstanding: the 401 handler, and the retry/timeout policy ----

test_that("a 401 discards the cached token so the next call re-authenticates", {
  secret_cache_clear()
  secret_cache_set(".token", "a-stale-entry")
  secret_cache_set(".token_minted_at", Sys.time())
  local_mocked_bindings(secretsR_token = fake_token,
                        gsm_perform = function(req, ...) http_err(401))
  expect_error(secret_get_gsm("studyflix-test"), "re-authenticate")
  expect_null(secret_cache_get(".token"))
  expect_null(secret_cache_get(".token_minted_at"))
})

test_that("the request carries the retry policy and timeout the comments claim", {
  # httr2 mocking short-circuits req_perform() before its retry loop, so retrying
  # cannot be observed by performing. Assert the policy on the request instead
  # and let httr2 own the looping.
  seen <- NULL
  local_mocked_bindings(
    secretsR_token = fake_token,
    gsm_perform = function(req, ...) { seen <<- req; ok_body() }
  )
  secret_get_gsm("studyflix-test")

  expect_equal(seen$options$timeout_ms, 10000)
  expect_equal(seen$policies$retry_max_tries, 3)
  expect_true(seen$policies$retry_on_failure)   # curl failures, incl. the timeout
  is_transient <- seen$policies$retry_is_transient
  for (status in c(408, 429, 500, 502, 503, 504)) {
    expect_true(is_transient(httr2::response(status_code = status)))
  }
  for (status in c(400, 401, 403, 404)) {
    expect_false(is_transient(httr2::response(status_code = status)))
  }
})

# ---- credential must never reach the log ----

test_that("a payload containing NUL is rejected, and the error carries no plaintext", {
  # rawToChar()'s own error embeds the decoded bytes - the credential - verbatim.
  local_mocked_bindings(
    secretsR_token = fake_token,
    gsm_perform = function(req, ...) list(payload = list(
      data = jsonlite::base64_enc(iconv("PGkey-LIVE-9f3a2b", "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]])))
  )
  msg <- tryCatch(secret_get_gsm("studyflix-test"), error = conditionMessage)
  expect_match(msg, "NUL bytes")
  expect_false(grepl("PGkey", msg, fixed = TRUE))
})

test_that("a trailing NUL is rejected rather than silently stripped", {
  local_mocked_bindings(
    secretsR_token = fake_token,
    gsm_perform = function(req, ...) list(payload = list(
      data = jsonlite::base64_enc(c(charToRaw("hunter2"), as.raw(0)))))
  )
  expect_error(secret_get_gsm("studyflix-test"), "NUL bytes")
})

test_that("the response body is not printed even when HTTR2_VERBOSITY is set", {
  # The body IS the secret, and httr2 prints it at verbosity 2+. Driven over a
  # file:// URL because httr2's mock seam emits no verbose output at all, so a
  # mocked test would pass with or without the fix.
  p <- withr::local_tempfile(fileext = ".json")
  writeLines('{"payload":{"data":"aHVudGVyMg=="}}', p)
  p <- normalizePath(p, winslash = "/")
  url <- if (grepl("^/", p)) paste0("file://", p) else paste0("file:///", p)
  withr::local_options(httr2_verbosity = 3)
  out <- capture.output(try(gsm_perform(httr2::request(url)), silent = TRUE), type = "output")
  expect_length(out, 0)
})

# ---- failures that used to surface anonymously ----

test_that("an exhausted 5xx still names the secret, the status and the project", {
  local_mocked_bindings(secretsR_token = fake_token,
                        gsm_perform = function(req, ...) http_err(500))
  msg <- tryCatch(secret_get_gsm("studyflix-test"), error = conditionMessage)
  expect_match(msg, "HTTP 500")
  expect_match(msg, "studyflix-test")
  expect_match(msg, "studyflix-secrets")
})

test_that("the specific handlers still win over the terminal one", {
  # tryCatch keeps sibling handlers established, so a terminal `error =` handler
  # would re-wrap these. Keying on the httr2 classes must not.
  local_mocked_bindings(secretsR_token = fake_token,
                        gsm_perform = function(req, ...) http_err(403))
  msg <- tryCatch(secret_get_gsm("studyflix-test"), error = conditionMessage)
  expect_match(msg, "secretAccessor")
  expect_false(grepl("failed after retries", msg, fixed = TRUE))
})

test_that("a file-backend-internal name is refused before any request", {
  local_mocked_bindings(secretsR_token = fake_token,
                        gsm_perform = function(req, ...) stop("the network must not be reached"))
  expect_error(secret_get_gsm("file:postgresql-credentials"), "file-backend-internal")
})
