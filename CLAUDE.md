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
  `%LOCALAPPDATA%Programs\R\R-4.6.1\bin\Rscript.exe`.
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

Baseline: **123 passing, 2 skipped, check 0/0/0** (v0.2.0, 2026-08-20).
Integration tests run only with `SECRETSR_INTEGRATION=1` and need GCP access to
`studyflix-secrets`; that run was 111 at v0.1 and has not been re-measured since.

**Keep this number current.** It was left at 66 through two commits that added 51
tests, and a review then cited the stale figure to call a correct expectation
unmeetable. A test count that lies is worse than no test count.

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
  who can set environment variables for a job (see the infrastructure repo's
  server notes for why that is reachable) satisfies the backend guard with
  `SF_SECRET_BACKEND=gsm` and repoints the package at a project they control.
- **The cache key must contain everything that changes what a name resolves
  to**: backend, project, name, version, a real hash of `file_key`, and — for
  the `file` backend only — `getwd()`. Two defects lived here until 2026-08-20.
  `digest_key()` was first-character-code plus length, so `"password-a"` and
  `"password-b"` both produced `"112-10"` and shared a slot; on the Shiny path
  `args` carries a *per-user* key, making that a cross-user credential leak.
  And the legacy map holds **relative** paths, so without `getwd()` two app
  roots in one process collapsed to one entry. Both are mutation-tested; each
  component fails exactly one test when removed. `getwd()` is excluded for
  `gsm`/`env` deliberately — there it would turn a directory change into an API
  call, and a third test pins that.
- **`secret_get()` is the primary export.** Two others: `secret_cache_clear()`,
  so a long-running process can pick up a rotated secret, and `secret_backend()`
  (v0.2.0), so a consumer can branch on the backend without reaching into `:::`
  or re-implementing the resolution rules. `secret_backend()` is a *report*, not
  a permission — `secret_get()` still enforces the production guard, so knowing
  the backend cannot be used to bypass it. Keep the export list this short.
- **The legacy map covers all 22 dispatched services.** `msgraph_sharepoint`
  (Billomatics PR #32) and `gemini` were added in v0.2.0. Deliberate absences are
  documented in `R/legacy_map.R`'s roxygen and each has a reason; a name missing
  without one is a bug, because `authentication_process()` dispatches it and the
  equivalence test in design §5.5 will fail on it.
- **There are TWO legacy data keys**, `studyflix-legacy-data-key-billomat` and
  `-asana`. Established 2026-08-20 by sweeping every
  `encrypt_object()`/`decrypt_object()` call site org-wide: ~49 pass
  `keys$billomat[1]`, 9 pass `keys$asana[1]`. Under design §3.3 those are
  different strings, so a single data key would leave `base-02`'s output
  unreadable. Neither is in the map — each *is* a `file_key`, not a file.

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

## Server findings — kept out of this repository

Everything measured on the production host — what is installed there, what the
working directories are, what egress works, what the `keys/` layout looks like,
and which defences are not yet in place — lives in the **private** infrastructure
repository at `docs/gsm-server-findings.md`, not here.

That is deliberate. This package is public. Those notes name the host and
describe how credentials can be harvested from a running job, and that remains
true until cutover — while public git history is permanent. The package source
is safe to publish; the operational reconnaissance is not.

Read `Shiny-0-studyflix-infrastructure/docs/gsm-server-findings.md` before doing
anything that touches the server, and record new measurements there rather than
in this file.

## House rules

`~/.claude/CLAUDE.md` governs. Two clarifications for this repo:

- The `do/` / `func/` folder standard applies to *applications*. This is an R
  package modelled on `PubPackR/dbconnectorR`, so `R/`, `man/`, `tests/` are
  correct.
- The `<<-` ban is flat and package code uses none. Test helpers use `<<-` into
  the `test_that` frame, which is idiomatic testthat and outside the rule's reach.

Every function carries roxygen with `@param`/`@return` and a `# ---- start ---- #`
marker; internals are `@noRd`.
