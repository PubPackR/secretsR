# secretsR

Credential resolution for Studyflix R applications. One function, three
interchangeable backends.

```r
secret_get("studyflix-billomat-api-key")
```

Part of the Google Secret Manager migration — see
`Shiny-0-studyflix-infrastructure/docs/superpowers/specs/2026-08-07-google-secret-manager-design.md`
(Plan C1).

## Backends

Chosen per process by `SF_SECRET_BACKEND`. **Never set it machine-wide.**

| Value | Source | When |
|---|---|---|
| `gsm` | Google Secret Manager | Production. The destination. |
| `file` | legacy `safer`-encrypted `keys/*` | Transition and rollback only. Deleted in Plan F. |
| `env` | `SF_SECRET_<NAME>` | Unit tests and break-glass. **Not a deployment mechanism.** |

Unset means `file`. There are no `.env` files anywhere in this design.

## Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `SF_SECRET_BACKEND` | `file` | Which backend to use |
| `SF_GSM_PROJECT` | `studyflix-secrets` | Project holding the secrets |
| `SF_SECRET_FILE_KEY` | — | `file` backend only: the `safer` master password |

`secret_get()` also takes `file_key` directly, which is how
`Billomatics::authentication_process(args)` threads the password through during
the transition.

## The default backend needs configuration

A fresh install with no environment set resolves to the `file` backend, which
**errors** unless `SF_SECRET_FILE_KEY` or a `file_key` argument is supplied.
That is by design, not a fault: nothing should silently fall back to a source it
was not told to use.

## Authentication

Application Default Credentials, always — never a hardcoded key path. The same
code works in three places:

```
laptop   gcloud auth application-default login
server   GOOGLE_APPLICATION_CREDENTIALS -> service-account key
GCP      metadata server, attached service account
```

That is what makes the eventual FlowForce-to-GCP move a matter of deleting one
file rather than changing code.

The credential chain is deliberately pruned to `{app_default, gce}` for the
duration of each call. gargle's default chain ends with
`credentials_user_oauth2`, which opens an interactive browser flow — in an
unattended job that hangs instead of crashing.

## Version pinning

`latest` resolves to the highest version number **regardless of state**, so a
disabled newest version makes access fail rather than fall back. For incident
response, pin:

```r
secret_get("studyflix-postgresql-connection", version = "3")
```

## Rotation in a long-running process

`secret_get()` memoises per process. A Shiny app or scheduled job will therefore
keep serving a cached value after a secret is rotated. Flush it:

```r
secret_cache_clear()
```

## Development

```r
devtools::test()
options(buildtools.check = function(action) TRUE)   # if Rtools is absent
devtools::check(args = "--no-manual", error_on = "warning")
```

Integration tests hit the real project and are skipped unless
`SECRETSR_INTEGRATION=1` is set.
