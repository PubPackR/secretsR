# secretsR — context for a new session

Credential resolution for Studyflix R applications. One exported function,
`secret_get()`, backed by three interchangeable sources. This is **Plan C1** of
the Google Secret Manager migration.

## Read these first

The design lives in the infrastructure repo, not here:

- `Shiny-0-studyflix-infrastructure/docs/superpowers/specs/2026-08-07-google-secret-manager-design.md`
  — §5.1–5.4, §5.10, §5.13 are what this package implements. **Read §5.3 before
  touching authentication.**
- `.../specs/2026-08-10-gsm-iam-matrix.md` — which principal gets which secret.
- `.../specs/2026-08-14-gsm-key-custody.md` — service-account key rules.
- `.../plans/2026-08-17-secretsr-package.md` — the plan this was built from,
  with a revision history of what two earlier versions got wrong.

## Environment (verified 2026-08-18, Windows dev machine)

- **`Rscript` is not on `PATH`.** Use
  `C:\Users\KEMP110\AppData\Local\Programs\R\R-4.6.1\bin\Rscript.exe`.
- **Rtools is not installed.** `devtools::check()` aborts without it even for a
  pure-R package. Bypass with `options(buildtools.check = function(action) TRUE)`.
- Invoke R from **PowerShell**; use **Git Bash** for git/gcloud.
- Keep every `Rscript -e` string on **one line** — a multi-line one segfaults
  here (exit 139).
- gargle 1.6.1, httr2 1.2.3, testthat 3.3.2, roxygen2 8.0.0.

```powershell
$R = "$env:LOCALAPPDATA\Programs\R\R-4.6.1\bin\Rscript.exe"
& $R -e "devtools::test()"
& $R -e "options(buildtools.check=function(a) TRUE); devtools::check(args='--no-manual', error_on='warning')"
```

Baseline: **66 passing, 2 skipped, check 0/0/0.** Integration tests run only with
`SECRETSR_INTEGRATION=1` and need GCP access to `studyflix-secrets`.

## The discipline that matters here

**Three separate rounds of this package's design shipped a guard that could not
fail.** Each time the tests were green and the constraint was violated:

1. `token_fetch(cred_funs = ...)` — an argument that does not exist, so the
   credential chain was never pruned. The tests asserted on arguments passed to
   our own wrapper, so they passed.
2. A token cache added later meant the pruning tests got cache hits and their
   mocks never fired — two errored, one passed vacuously.
3. The restoration test read its baseline *after* an earlier test had already
   mutated the registry, so a session-global `cred_funs_set()` compared pruned to
   pruned and passed.

**So: after changing anything in `R/backend_gsm.R`, deliberately break it and
confirm the tests fail.** Reading is not sufficient — all three survived careful
review and died in seconds under mutation.

Known-good mutations, with expected results:

| Mutation | Expected |
|---|---|
| `local_cred_funs(...)` → `cred_funs_set(...)` | 4 failures in `test-backend_gsm-token.R` |
| delete the `local_cred_funs` line | 2 failures |

## Invariants that must not regress

- **The credential chain is pruned to `{app_default, gce}` for the duration of
  each call, and restored after.** gargle's default chain ends with
  `credentials_user_oauth2`, which opens a browser — in an unattended FlowForce
  job that *hangs instead of crashing*. Use `local_cred_funs()`, never
  `cred_funs_set()`, or `bigrquery`/`googlesheets4` in the same process lose
  their auth chain permanently.
- **No path returns `NA`, `NULL` or `""`.** Enforced centrally in
  `secretsR_validate()`. The defect this guards is real: a `"google sheets"` typo,
  or version skew between the installed and expected Billomatics, makes
  `authentication_process()` return bare `NA` with no error at all.
- **No credential value reaches any message, warning, error or console output.**
  The check is in the plan's Task 7 Step 6 — it greps for payload-bearing
  variables interpolated into `stop`/`warning`/`message`, not for the words
  themselves.
- **`SF_GSM_PROJECT` is honoured only outside production.** Otherwise an actor
  who can set env vars for a job (FlowForce's `:4647` is internet-reachable)
  satisfies the backend guard with `SF_SECRET_BACKEND=gsm` and repoints the
  package at a project they control.
- **`secret_get()` is the primary export**; `secret_cache_clear()` is the only
  other, so a long-running process can pick up a rotated secret.

## Outstanding — not yet done

Two independent reviews found more than has been fixed.

**Test-coverage gaps** — four of five closed in `f20bdd7`; one remains:

- ~~No test for the `httr2_http_401` handler.~~ Closed: asserts the message and
  that `.token` **and** `.token_minted_at` are `NULL` afterwards.
- ~~`req_timeout()` and `req_retry()` are unasserted.~~ Closed: the request is
  captured and `retry_max_tries`, `retry_on_failure`, `retry_is_transient` and
  `timeout_ms` are all asserted. Note this pins *configuration*, not behaviour —
  httr2's mock seam short-circuits `req_perform()` before the retry loop, so
  retrying cannot be observed by performing. Verified on httr2 1.2.3 and 1.3.0.
- ~~The §5.2-mandated WARN is unasserted.~~ Closed, including the once-per-process
  throttle. It is captured from **stdout**: log4r's default console appender
  writes there. Without log4r installed, `secretsR_warn()` degrades to
  `warning()`, which goes to stderr — the two paths do not agree on a stream.
- ~~`secret_get_file()`'s default `file_key` is never exercised.~~ Closed.
- **STILL OPEN** — three empty-string tests are **vacuous on Windows**:
  `withr::with_envvar(c(X = ""))` *unsets* the variable here, so they take the
  `is.na` path and never reach the `nzchar()` guard they were written for. The
  behaviour is real on the Linux server. Either test the logic directly or
  `skip_on_os("windows")` with a note.

**Design items deferred:**

- **No TTL on cached secret values.** A Shiny process serves a rotated secret
  indefinitely, and the failure then surfaces at the DB/API connect, far from the
  cause. `secret_cache_clear()` exists but nothing calls it and no Shiny recipe
  ships.
- **The `file` backend's `../../keys/` path is working-directory dependent**, and
  the cache hides it: one successful early call makes later calls succeed
  regardless of `cwd`. Consider anchoring on `SF_KEYS_DIR` with the relative path
  as fallback.
- A plaintext value lives in the cache environment for the process lifetime, so
  `options(error = dump.frames)` in a FlowForce job would serialise it into
  `last.dump.rda`. Worth a README note.

## Verified on the server 2026-08-19 — do not re-derive

Measured directly on `shiny.studyflix.info`. These were open questions; three are
now closed.

- **Dependencies are installed on the host** despite appearing in no install
  list: gargle 1.6.1, httr2 **1.3.0**, jsonlite 2.0.0, safer 0.2.2, log4r 0.5.0,
  withr 3.0.3, testthat 3.3.2, remotes 2.4.2.1. Note httr2 is *newer* than the
  1.2.3 used for development; its `req$policies` names are unchanged, so the
  retry-policy assertions hold on both.
- **HTTPS egress to `secretmanager.googleapis.com` works from the host** (GET →
  401, i.e. reached Google unauthenticated) **and from inside the `application`
  container** on the `protected` network. The container has **no `curl`**; use
  `docker exec application Rscript -e '...'` instead. Beware: base R's
  `curlGetHeaders()` issues a **HEAD**, and Google answers HEAD on that path with
  **404** — reproduced identically off-server, so a 404 there means nothing.
  A GET is the only meaningful probe; 401 is the pass.
- **The server has no GCP credentials at all** — `GOOGLE_APPLICATION_CREDENTIALS`
  is unset and there is no gcloud ADC file. So `secretsR_is_production()` is
  currently FALSE there, `SF_GSM_PROJECT` is honoured, and the production guard
  is inert on the server until a key or the marker lands.
- **`studyflix-secrets` contains exactly one secret**, `secretsr-integration-test`
  (v1 enabled = `round-trip-ok`, v2 disabled), created 2026-08-19 to make the
  integration tests runnable. Nothing real has been migrated into GSM yet.
- **The live GSM path works end to end from a dev machine** under a *user* ADC:
  111 tests pass with `SECRETSR_INTEGRATION=1`, including the disabled-`latest`
  case. The service-account path remains unrun.
- **The `application` container has the dependencies too**, at the same versions
  as the host except log4r: gargle 1.6.1, httr2 1.3.0, jsonlite 2.0.0,
  safer 0.2.2, log4r **0.4.4** (host has 0.5.0). Since log4r is a Suggests with a
  `warning()` fallback, the drift is harmless — but do not assume host versions
  apply inside the container.
- **The server shell is `dash`, not bash.** `read -s` fails with "Illegal
  option -s"; use `stty -echo; read VAR; stty echo` to enter a secret without
  echoing. Do not paste `<placeholder>` angle brackets into it either — `sh`
  reads them as redirections and dies with "Syntax error: newline unexpected".

**Belongs to Plan C3, not here:**

- `gargle` and `httr2` appear in **no** server install list — zero hits in
  `ansible/install-r-packages.yml` and `shiny-server/Dockerfile` — though both
  are in fact installed on the host (see above). The container is unconfirmed.
- `/etc/studyflix/production` must exist on production hosts. The Shiny container
  mounts neither it nor an `environment:` block, which is why the production
  signal also accepts a readable `GOOGLE_APPLICATION_CREDENTIALS`.
- HTTPS egress to `secretmanager.googleapis.com` from the `protected` Docker
  network is unverified.

## What cannot be tested from a dev machine

- **The service-account auth path.** Everything so far ran on a *user* ADC
  (`gcloud auth application-default login`). Production uses
  `GOOGLE_APPLICATION_CREDENTIALS` pointing at a service-account key. A review
  verified with a synthetic key that `credentials$access_token` is populated
  identically, so `secretsR_access_token()` should work — but it has never run for
  real. Service-account JWT auth is also clock-skew sensitive, which a laptop with
  working NTP will never reveal.
- **The `file` backend end-to-end.** It is the *default* backend and has only ever
  been tested against mocks. The complete `keys/` folder exists only on
  `shiny.studyflix.info`; a dev machine has 3 of ~20 locations.
- **The production guard**, which needs a real marker file or a real key.

## House rules

`~/.claude/CLAUDE.md` governs. Two clarifications for this repo:

- The `do/` / `func/` folder standard applies to *applications*. This is an R
  package modelled on `PubPackR/dbconnectorR`, so `R/`, `man/`, `tests/` are
  correct.
- The `<<-` ban is flat and package code uses none. Test helpers use `<<-` into
  the `test_that` frame, which is idiomatic testthat and outside the rule's reach.

Every function carries roxygen with `@param`/`@return` and a `# ---- start ---- #`
marker; internals are `@noRd`.
