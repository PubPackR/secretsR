test_that("a value survives within the process", {
  secret_cache_clear(); secret_cache_set("k", "v")
  expect_equal(secret_cache_get("k"), "v")
})

test_that("a missing key returns NULL", {
  secret_cache_clear()
  expect_null(secret_cache_get("absent"))
})

test_that("clear empties the cache, including dot-prefixed keys", {
  secret_cache_set("k", "v"); secret_cache_set(".token", "t")
  secret_cache_clear()
  expect_null(secret_cache_get("k")); expect_null(secret_cache_get(".token"))
})

test_that("the cache does not fall through to the namespace", {
  secret_cache_clear()
  expect_null(secret_cache_get("secret_cache_get"))
})
