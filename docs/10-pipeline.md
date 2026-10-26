# Step 10 — The full pipeline

## The idea

Steps 1–9 each added a tool. This step makes them one system:

- **Every check runs on every change**, in parallel.
- **A single gate** decides whether the change is acceptable.
- **Only what passed the gate is published**, signed, with its SBOM.
- **The pipeline is code too**, and it is scanned like code.

## The pipeline

`.github/workflows/ci.yml`:

```
  build ─────────────┐   lint, unit tests, tsc, npm audit signatures
  workflows ─────────┤   actionlint + zizmor on ci.yml itself
  secrets ───────────┤   gitleaks on the whole git history
  sca ───────────────┤   Trivy on package-lock.json
  dependency-review ─┤   new vulnerable deps in a PR (PRs only)
  sast ──────────────┼──▶ gate ──▶ release
  image ─────────────┤      │       push to GHCR, Syft SBOM,
  iac ───────────────┤      │       Cosign keyless sign + attest, verify
  dast ──────────────┘      │       (push to main only)
                            └─ required status check
```

| Job | Tool(s) | Local equivalent | Breaks on |
|-----|---------|------------------|-----------|
| `build` | eslint, jest, tsc, npm | `npm run lint && npm test && npm run build` | Any error |
| `workflows` | actionlint, zizmor | `scripts/security/workflows.sh` | Any finding |
| `secrets` | gitleaks | `scripts/security/secrets.sh` | Any secret in history |
| `sca` | Trivy | `scripts/security/sca.sh` | Fixable HIGH/CRITICAL CVE |
| `dependency-review` | GitHub | (PRs only) | PR adds a HIGH+ vulnerable dep |
| `sast` | Semgrep | `scripts/security/sast.sh test && …/sast.sh` | Any finding, or a failing rule test |
| `image` | Trivy | `scripts/security/image.sh` | Dockerfile misconfig or fixable HIGH/CRITICAL CVE |
| `iac` | Terraform, Checkov, Conftest | `scripts/security/iac.sh` | Any failed check or policy |
| `dast` | OWASP ZAP | `scripts/stack.sh up && …/dast.sh` | Any rule set to FAIL in `.zap/rules.tsv` |
| `gate` | — | — | Any job above failed or was cancelled |
| `release` | Buildx, Syft, Cosign | `sbom.sh`, `sign-local.sh` | (runs only after the gate) |

Run every static check at once, like CI does:

```bash
scripts/security/all.sh
```

```
################ workflows.sh ################
################ secrets.sh history ################
################ sca.sh ################
################ sast.sh test ################
3/3: ✓ All tests passed
################ sast.sh scan ################
 • Findings: 0 (0 blocking)
################ image.sh ################
################ sbom.sh ################
################ iac.sh ################
Passed checks: 84, Failed checks: 0, Skipped checks: 6
All checks passed.
```

About 75 seconds on a warm cache.

## When each check runs

The table in the course, mapped to this repo:

| Moment | What runs | Where |
|--------|-----------|-------|
| `git commit` | gitleaks (staged), private key detection | pre-commit hook (step 2) |
| Pull request | Everything + dependency review | `ci.yml` |
| Push to `main` | Everything + release (sign, SBOM) | `ci.yml` |
| Every Monday 06:00 UTC | Everything, on unchanged code | `ci.yml` (`schedule`) |
| New CVE published | Dependabot alert + PR | `.github/dependabot.yml` |
| Weekly | Dependency / action / image / provider updates | `.github/dependabot.yml` |

The weekly run matters: a scan that passed last month says nothing
about the CVEs published since then.

## The gate

```yaml
gate:
  if: always()
  needs: [build, workflows, secrets, sca, dependency-review, sast, image, iac, dast]
```

Two details that are easy to get wrong:

- **`if: always()`**: without it, when a job fails the gate is
  *skipped*, and GitHub treats a skipped required check as **passing**.
  The gate must run in order to fail.
- **`skipped` is accepted**: `dependency-review` only runs on pull
  requests. The gate fails only on `failure` or `cancelled`.

### Make it mandatory

The gate only protects `main` if GitHub enforces it. In the repo:
*Settings → Rules → Rulesets → New branch ruleset*, target `main`:

- ✅ Require a pull request before merging
- ✅ Require status checks to pass → add **`Security gate`**
- ✅ Block force pushes

From then on, nothing reaches `main` (and therefore nothing is released)
without passing every check. Requiring only `Security gate`, instead of
each job, means adding a new job to the pipeline does not require
touching the ruleset.

## The pipeline is an attack target

A workflow can read secrets and publish releases, so it gets the same
treatment as application code:

| Protection | Where |
|------------|-------|
| `permissions: {}` at the top; each job asks for the minimum, with a comment | every job |
| Actions pinned by commit SHA (see the trivy-action incident in step 2) | every `uses:` |
| Tool images pinned by digest | `scripts/security/images.sh` |
| `persist-credentials: false` | every checkout |
| No `${{ }}` inside `run:` scripts; values go through `env:` (prevents script injection) | `gate`, `release` |
| `id-token: write` only on the job that signs | `release` |
| actionlint + zizmor on every change | `workflows` job |

zizmor found one real issue while building this step: permissions
without an explanatory comment (`undocumented-permissions`). Every
permission line now says why it exists.

## Results in GitHub

- **Actions tab**: each run, with the gate summary at the end.
- **Security → Code scanning**: findings from Trivy (`trivy-sca`,
  `trivy-image`, `trivy-dockerfile`), Semgrep and Checkov, linked to the
  line of code. Fixed findings close automatically.
- **Security → Dependabot**: CVE alerts on dependencies.
- **Artifacts** of each run: `zap-report` (HTML) and `sbom`.
- **Packages**: the signed image in `ghcr.io/omimauro/dev-secops`.

## What each tool caught in this repo

Not just exercises: several of these were real problems in the code as
it was written.

| Step | Tool | Finding | Real or exercise |
|------|------|---------|------------------|
| 2 | gitleaks | GitHub token and `JWT_SECRET`, also after deleting the file | Exercise |
| 3 | Trivy | `multer` CVE-2026-113872 (HIGH), transitive via NestJS | **Real**: fixed with `overrides` |
| 3 | — | `npm audit fix` turned 1 HIGH into 12 HIGH | **Real**: reverted |
| 4 | Semgrep | `synchronize: true` in production config | **Real**: fixed |
| 4 | Semgrep | SQL injection in search: only our custom rule saw it | Exercise (exploited: read other users' notes) |
| 5 | Trivy | `node:24` image: 4,863 CVEs vs 31 in distroless | Comparison |
| 6 | Cosign | Tampered image under the same tag: rejected | Exercise |
| 7 | Checkov | 8 issues in our Terraform: 3 fixed, 6 skipped with reasons | **Real** |
| 7 | gitleaks + Checkov | Missed a human-chosen Terraform password → new rule | **Real gap**: closed |
| 7 | Conftest | 4 organization rules broken by the insecure example | Exercise |
| 9 | ZAP | 500 on NUL bytes; missing security headers | **Real**: fixed |
| 9 | ZAP | Same SQL injection as step 4, from outside, with `'` | Exercise |
| 10 | zizmor | Undocumented workflow permissions | **Real**: fixed |

No single tool found everything. Each one looks from a different angle,
which is why they are combined.

## Metrics worth watching

DevOps metrics (lead time, MTTR) plus, for DevSecOps:

- **Time to patch**: from a CVE alert to the merged fix. Dependabot PRs
  and the weekly run make this measurable.
- **Open findings by severity** in the Security tab, over time.
- **Exceptions**: entries in `.trivyignore`, `#checkov:skip`,
  `nosemgrep`, `gitleaks:allow` and `.zap/rules.tsv`. Each one should have
  a reason; the ones in `.trivyignore` should also have an expiry date.

```bash
grep -rn "checkov:skip\|nosemgrep\|gitleaks:allow" --include='*.tf' --include='*.ts' . | grep -v node_modules
```

## What is next

This repo stops at the image. Running it securely in Kubernetes (RBAC,
NetworkPolicies, Falco runtime detection, admission control that only
accepts images signed by this pipeline) is the subject of the Kubernetes
course.
