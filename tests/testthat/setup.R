# No test may inherit cached state - in particular .token, whose presence makes
# the registry-pruning assertions pass vacuously.
withr::defer(secret_cache_clear(), teardown_env())
