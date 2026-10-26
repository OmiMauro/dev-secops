# Step 2 — Secrets in code (gitleaks + pre-commit)

## The problem

A credential committed to git is leaked **forever**, even if you delete
it in the next commit: it is still in the history, in every clone and in
every fork. Bots scan public GitHub repos for keys within minutes.

The only real fix for a leaked secret is to **rotate it** (revoke it and
issue a new one). Cleaning the history comes second.

## What was added

| File | Purpose |
|------|---------|
| `.gitleaks.toml` | gitleaks config: default rules + a custom `jwt-signing-secret` rule |
| `.pre-commit-config.yaml` | Git hooks run before each commit |
| `scripts/security/secrets.sh` | Runs gitleaks in Docker (`history` or `staged` mode) |
| `scripts/security/images.sh` | Pinned image of every security tool (tag + digest) |
| `scripts/security/lib.sh` | Shared helper to run a tool container on the repo |
| `.github/workflows/ci.yml` | New `secrets` job that scans the full history |

Two layers, on purpose:

```
 your machine                         GitHub
┌──────────────────────┐     push    ┌──────────────────────────────┐
│ pre-commit hook      │ ──────────▶ │ CI job "secrets"             │
│ scans staged changes │             │ scans the WHOLE history      │
│ fast, but skippable  │             │ slower, cannot be skipped    │
│ (--no-verify)        │             │ + GitHub push protection     │
└──────────────────────┘             └──────────────────────────────┘
```

## Setup

Install the pre-commit framework once (it is a Python tool):

```bash
sudo apt install pre-commit        # Debian/Ubuntu
# or: pipx install pre-commit
pre-commit install                 # activates the commit AND push hooks in this clone
```

The gitleaks hook calls `scripts/security/secrets.sh`, which runs gitleaks
inside Docker. Nothing else to install.

## Exercise: break it

Run this in a throwaway branch. The token is random, so it is not a real
credential, but it has the exact shape of a GitHub token:

```bash
git switch -c leak-test
printf 'export const config = {\n  githubToken: "ghp_%s",\n};\n' "$(openssl rand -hex 18)" > src/leak.ts
echo "JWT_SECRET=$(openssl rand -base64 36)" > src/env.local.txt
git add src/leak.ts src/env.local.txt
git commit -m "add leak"
```

The commit is **blocked**:

```
gitleaks (staged changes)................................................Failed
Finding:     JWT_SECRET=REDACTED
RuleID:      jwt-signing-secret          <- our custom rule
File:        src/env.local.txt

Finding:     githubToken: "REDACTED",
RuleID:      github-pat                  <- built-in rule
File:        src/leak.ts

WRN leaks found: 2
```

Now pretend you skipped the hook, then "fixed" it by deleting the files:

```bash
git commit --no-verify -m "add leak"
git rm src/leak.ts src/env.local.txt
git commit --no-verify -m "remove leak"
scripts/security/secrets.sh history
```

The files are gone, but gitleaks still finds both secrets in the history:

```
RuleID:      github-pat
File:        src/leak.ts
Commit:      19d15f93a2067807e0fd8e7df660665ba3e6b268
WRN leaks found: 2
```

This is exactly what the CI job does on every push. Clean up with:

```bash
git switch main && git branch -D leak-test
```

## If a real secret leaks

1. **Rotate it first.** Revoke the key at the provider. Assume it is
   already compromised.
2. Remove it from the code and load it from the environment (or Vault,
   see step 8).
3. Optionally rewrite history with
   [`git filter-repo`](https://github.com/newren/git-filter-repo) and
   force-push. Forks and existing clones keep the old commits, which is
   why step 1 matters more.

## False positives

- One line: add the comment `// gitleaks:allow` at the end of the line.
- A known finding: add its `Fingerprint` to a `.gitleaksignore` file.
- A whole file: add a path to `[[allowlists]]` in `.gitleaks.toml`.
  Keep this list short.

## GitHub's own layer

Public repositories get **secret scanning** and **push protection** for
free: GitHub rejects a `git push` that contains a token from a known
provider. Check it under *Settings → Advanced Security*. It only knows
public token formats, so our custom `JWT_SECRET` rule still matters.

## Why images are pinned by digest

`scripts/security/images.sh` pins every tool as `tag@sha256:digest`.
In March 2026 attackers force-pushed 76 version tags of
`aquasecurity/trivy-action` to malicious code that stole CI secrets
([CVE-2026-33634](https://www.aquasec.com/blog/trivy-supply-chain-attack-what-you-need-to-know)).
Pipelines using `@v0.x` tags ran the malware; pipelines pinned to a
SHA did not. Security tools are a supply chain too.

## Lesson learned later: a scanner that cannot scan

While working on the Dependabot PRs in a `git worktree`, the pre-commit
hook said `no leaks found` for a commit that **did** contain a token.
Inside the container git could not read the repository (a worktree's
`.git` points outside the mounted folder), and gitleaks reacted like this:

```
ERR [git] fatal: not a git repository: .../.git/worktrees/-lab-pr
INF no leaks found          ← exit code 0
```

It **failed open**: it scanned nothing and reported success. Two fixes in
`scripts/security/secrets.sh`:

1. Mount the real git directory when the repo is a worktree.
2. **Fail closed**: any `ERR` line from gitleaks fails the script, even
   if it claims there were no leaks.

Lesson: test that your security checks can fail. A check that never
fails might not be running at all.
