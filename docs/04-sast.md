# Step 4 — SAST (Semgrep)

## The problem

SCA (step 3) finds bugs in **other people's** code. SAST (Static
Application Security Testing) looks for dangerous patterns in **our**
code: SQL injection, `eval`, weak crypto, disabled checks... without
running it, by reading the source like a very strict reviewer.

[Semgrep](https://semgrep.dev) rules are written in the same syntax as
the code they match, which makes them easy to read and to write.

## What was added

| File | Purpose |
|------|---------|
| `scripts/security/sast.sh` | `scan` (community + custom rules, gate) and `test` (rule tests) |
| `.semgrep/rules/*.yml` | Three custom rules for this codebase |
| `.semgrep/rules/*.ts` | Test cases for each rule (`ruleid:` must match, `ok:` must not) |
| `ci.yml` → `sast` job | Tests the rules, scans `src/`, uploads SARIF |
| `src/config/database.config.ts` | Fixed a real finding (see below) |

Rules used:

- Community packs from the Semgrep Registry: `p/typescript`, `p/nodejs`,
  `p/owasp-top-ten` (~600 rules).
- Our own rules in `.semgrep/rules/`:

| Rule | Catches |
|------|---------|
| `typeorm-sql-injection` | `.query()` / `.where()` / `.orderBy()`... built with `${}` or `+` |
| `typeorm-synchronize-enabled` | `synchronize: true` hardcoded in a TypeORM config |
| `jwt-ignore-expiration` | `jwt.verify(..., { ignoreExpiration: true })` |

## A real finding

The first scan with our rules failed on our own code:

```
src/config/database.config.ts
❯❯❱ semgrep.rules.typeorm-synchronize-enabled
      ❰❰ Blocking ❱❱
      `synchronize: true` lets TypeORM alter the database schema on every start...
```

Fixed by enabling it only outside production:

```ts
synchronize: config.get<string>('NODE_ENV') !== 'production',
```

## Exercise: break it (SQL injection)

Replace `findAllForUser` in `src/modules/notes/services/notes.service.ts`
with this version. It looks harmless and it compiles:

```ts
findAllForUser(userId: string, search?: string): Promise<Note[]> {
  const qb = this.notesRepository
    .createQueryBuilder('note')
    .where('note.ownerId = :userId', { userId });
  if (search) {
    qb.andWhere(`note.title ILIKE '%${search}%'`);   // ← the bug
  }
  return qb.orderBy('note.updatedAt', 'DESC').getMany();
}
```

Scan:

```
$ scripts/security/sast.sh
❯❯❱ semgrep.rules.typeorm-sql-injection
     25┆ qb.andWhere(`note.title ILIKE '%${search}%'`);
 • Findings: 1 (1 blocking)
```

**Only our custom rule catches it.** None of the ~600 community rules
know TypeORM's query builder. This is why teams write rules for their own
stack.

### Is it really exploitable? Yes.

With the vulnerable code running, user *alice* searches for
`x' OR 'a' ILIKE 'a`:

```bash
curl -G -H "Authorization: Bearer $ALICE" \
  --data-urlencode "search=x' OR 'a' ILIKE 'a" localhost:3000/api/notes
```

The SQL becomes `... WHERE ownerId = $1 AND title ILIKE '%x' OR 'a' ILIKE 'a%'`,
and `OR` makes the owner check irrelevant. Alice gets **every user's notes**:

```json
[{"title":"Victim secret note","content":"bank PIN 1234", ...},
 {"title":"Primera nota","content":"hola", ...}]
```

With the original code (`ILike(...)`, a bound parameter) the same request
returns `[]`. Restore it with `git checkout src/modules/notes`.

## Writing a rule

`.semgrep/rules/jwt-ignore-expiration.yml` is the simplest one:

```yaml
rules:
  - id: jwt-ignore-expiration
    message: JWT verification with ignoreExpiration: true accepts expired tokens forever.
    severity: ERROR
    languages: [typescript]
    pattern-either:
      - pattern: '$JWT.verifyAsync($TOKEN, {..., ignoreExpiration: true, ...})'
```

- `$JWT`, `$TOKEN` are metavariables: they match any expression.
- `...` matches any number of arguments or object properties.
- Patterns with `:` or quotes must be quoted in YAML.

Next to it, `jwt-ignore-expiration.ts` holds the test cases:

```ts
// ruleid: jwt-ignore-expiration
await jwtService.verifyAsync(token, { ignoreExpiration: true });

// ok: jwt-ignore-expiration
await jwtService.verifyAsync(token);
```

`scripts/security/sast.sh test` fails if a `ruleid:` line is not matched
or an `ok:` line is. While writing these rules the test caught a real
mistake: a `metavariable-regex` on `$METHOD` was silently discarding the
`.query()` branch, where `$METHOD` does not exist.

Try the [Semgrep playground](https://semgrep.dev/playground) to
experiment with patterns.

## False positives

Add a comment on the line above, always with the reason:

```ts
// nosemgrep: typeorm-sql-injection -- column name comes from an enum allowlist
qb.orderBy(`note.${sortColumn}`);
```

## SAST limits

- It does not know runtime values: it cannot tell whether a variable is
  user input or a constant (taint-mode rules help with that).
- It does not see configuration, deployed infrastructure or the
  running app. That is what IaC scanning (step 7) and DAST (step 9) are for.
- SonarQube is the other big name; it adds code quality metrics and a
  server with history, at the cost of running that server.

## Pinning the community rules

`--config p/typescript` downloads whatever the Semgrep Registry serves
**today**. Rules get added, changed and removed upstream, so the same code
can pass on Monday and fail on Tuesday, and nobody can tell why.

`.semgrep/registry.lock` pins each pack by SHA-256, like `package-lock.json`
pins npm packages:

```
967e551f37a9...  typescript.yml
f8d691f09ab5...  nodejs.yml
72de2b065f49...  owasp-top-ten.yml
```

`sast.sh` downloads the packs, checks them against the lock and only then
scans. When a pack changes upstream:

```
Semgrep registry rules changed upstream:
< 967e551f37a9...  typescript.yml
> 067e551f37a9...  typescript.yml
Review the new rules, then run: scripts/security/sast.sh update-lock
```

Updating the lock is a deliberate commit that can be reviewed, instead of
a silent change in CI. The packs themselves are not committed: the
Semgrep Rules License does not allow redistributing them.
