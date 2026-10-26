# Step 9 — DAST (OWASP ZAP)

## The problem

Every tool so far read **files**: code, lockfiles, Dockerfile, Terraform.
None of them ever saw the application running: the real HTTP headers,
how it reacts to strange input, what the database says when it gets a
byte it did not expect.

**DAST (Dynamic Application Security Testing)** attacks the running app
from the outside, like an attacker would, knowing nothing about the code.

## What was added

| File | Purpose |
|------|---------|
| `src/config/swagger.ts` | OpenAPI spec at `/api/docs-json` (only if `SWAGGER_ENABLED=true`) |
| `nest-cli.json` → `@nestjs/swagger` plugin | Generates the schemas from the DTOs |
| `scripts/security/dast.sh` | Creates a scan user, runs the ZAP API scan with its token |
| `.zap/rules.tsv` | Which alerts FAIL the build, which only WARN, and why |
| `src/main.ts` → `helmet()` | Security headers (fix for ZAP findings) |
| `src/common/validators/no-null-bytes.decorator.ts` | Fix for a crash found by ZAP |
| `ci.yml` → `dast` job | Starts the full stack and scans it; HTML report as artifact |

## How the scan works

```
dast.sh
 ├─ register + login a throwaway user → JWT
 └─ docker run zaproxy  (inside the stack's Docker network)
      ├─ reads http://api:3000/api/docs-json   → every endpoint and parameter
      ├─ adds "Authorization: Bearer <JWT>"    → tests what is behind the login
      ├─ passive scan: every response (headers, errors, leaks)
      └─ active scan: SQLi, XSS, command injection, path traversal... on every parameter
```

The OpenAPI spec matters: without it ZAP has to guess URLs. The Swagger
plugin even exports the validation rules (`maxLength: 200`...), so ZAP
knows what valid input looks like and where to push.

## Running it

```bash
SWAGGER_ENABLED=true scripts/stack.sh up
scripts/security/dast.sh
open reports/zap/report.html        # or xdg-open
```

## What it found in this repo

The first scan of the app as it was after step 8:

```
WARN-NEW: A Server Error response code was returned by the server [100000] x 2
WARN-NEW: X-Content-Type-Options Header Missing [10021] x 4
WARN-NEW: Server Leaks Information via "X-Powered-By" HTTP Response Header Field(s) [10037] x 9
WARN-NEW: Cross-Origin-Resource-Policy Header Missing or Invalid [90004] x 4
```

### 1. A crash nobody had seen (`100000`)

```
GET  /api/notes?search=%00   → 500
POST /api/notes  (content with %00) → 500
QueryFailedError: invalid byte sequence for encoding "UTF8": 0x00
```

A NUL byte is valid in a JavaScript string but PostgreSQL text columns
reject it. Not exploitable (the query is parameterized), but unhandled
input reaching the database and producing 500s is a robustness bug, and
a flood of 500s hides real attacks in the logs. Unit tests, SAST and
code review all missed it: nobody thinks of sending `%00`. ZAP sends it
to every parameter.

Fix: `@NoNullBytes()` on the note DTOs → now a clean `400 Bad Request`.

### 2. Missing hardening headers (`10021`, `10037`, `90004`)

Before:

```
X-Powered-By: Express
Content-Type: application/json; charset=utf-8
```

After `app.use(helmet())`:

```
Content-Security-Policy: default-src 'self'; ...
Cross-Origin-Resource-Policy: same-origin
Strict-Transport-Security: max-age=31536000; includeSubDomains
X-Content-Type-Options: nosniff
```

`X-Powered-By` is gone: no need to tell attackers which framework to
look up exploits for.

### 3. A finding that needed triage (`40014`)

After the fixes, one new alert appeared:

```
FAIL-NEW: Cross Site Scripting Weakness (Persistent in JSON Response) [40014]
  attack: <script>alert(1);</script>
  "Raised with LOW confidence as the Content-Type is not HTML."
```

ZAP created a note containing `<script>` and got it back in a JSON list.
Is it a vulnerability? **Not in this API**: it only answers
`application/json` with `nosniff`, so no browser executes it. It would be
in a frontend that inserts note content as HTML. Decision, written down
in `.zap/rules.tsv`: rule `40014` is WARN, so it stays visible but does
not break the build. Revisit if the API ever returns HTML.

This is what DAST work usually looks like: most of the time goes into
deciding what is real.

## Final result

```
WARN-NEW: Cross Site Scripting Weakness (Persistent in JSON Response) [40014] x 2
FAIL-NEW: 0   WARN-NEW: 1   PASS: 119
```

## Exercise: break it

Put the step 4 SQL injection back into `NotesService.findAllForUser`
(the `andWhere` with `${search}`), rebuild and scan:

```bash
SWAGGER_ENABLED=true scripts/stack.sh up      # rebuilds the image
scripts/security/dast.sh
```

```
FAIL-NEW: A Server Error response code was returned by the server [100000] x 1
FAIL-NEW: SQL Injection [40018] x 1
  GET /api/notes?search=%27   param: search   attack: '
exit 1
```

ZAP found the same bug as Semgrep, **without reading a single line of
code**: one quote character broke the query.

| | Semgrep (step 4) | ZAP (this step) |
|-|------------------|-----------------|
| Needs | The source code | A running app |
| Found the SQL injection | Yes, with our custom rule | Yes, with a `'` |
| Points to | The exact line | The URL and parameter |
| Speed | Seconds, on every push | Minutes, needs the whole stack |
| Sees headers, runtime config, DB errors | No | Yes |

Restore the code with `git checkout src/modules/notes`.

## Rules file

`.zap/rules.tsv`, tab separated:

```
40018	FAIL	SQL Injection
100000	FAIL	A Server Error response code was returned by the server
10021	FAIL	X-Content-Type-Options Header Missing
40014	WARN	Cross Site Scripting (Persistent) - see comment above
```

Headers fixed in this step are set to FAIL so they cannot regress
silently: remove `helmet()` and the build breaks.

## Only scan what you own

ZAP's active scan sends real attacks. Run it against your own local or
test environments, never against a system you do not have written
permission to test.

## Rate limiting vs DAST

Since the API limits `/auth/*` to 5 requests per minute per IP, ZAP's
attacks against login and register were mostly answered with
`429 Too Many Requests`: the limit works against a scanner exactly as it
does against an attacker, and those routes were barely tested.

The limits are configurable (`THROTTLE_LIMIT`, `AUTH_THROTTLE_LIMIT`) and
the `dast` job raises them **only for the scan**:

```bash
SWAGGER_ENABLED=true THROTTLE_LIMIT=100000 AUTH_THROTTLE_LIMIT=100000 scripts/stack.sh up
```

With the defaults the 6th login attempt in a minute gets a 429
(`Retry-After: 60`); with the raised limits ZAP got no 429 at all. Never
raise them in production.

Note that ZAP never reported the *missing* rate limit before it was
added: scanners find broken behavior, not absent controls. Brute-force
protection had to come from reviewing the design.
