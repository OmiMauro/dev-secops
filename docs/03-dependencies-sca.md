# Step 3 — Dependencies and SCA (Trivy, Dependabot)

## The problem

Our own code is a few hundred lines. `node_modules` is **hundreds of
packages** written by strangers. A known vulnerability (CVE) in any of
them is a vulnerability in our app.

**SCA (Software Composition Analysis)** compares the exact versions in
`package-lock.json` against public vulnerability databases.

## What was added

| File | Purpose |
|------|---------|
| `scripts/security/sca.sh` | Trivy scan of `package-lock.json` + gate on HIGH/CRITICAL |
| `scripts/security/lib.sh` | `run_trivy` (with cache) and `trivy_report_and_gate` helpers |
| `.trivyignore` | Accepted risks, each with a reason and an expiry date |
| `.github/dependabot.yml` | Weekly update PRs for npm packages and GitHub Actions |
| `package.json` → `overrides` | Forces the patched `multer` (see below) |
| `ci.yml` → `sca` job | Runs the scan, uploads SARIF to the Security tab |
| `ci.yml` → `dependency-review` job | On PRs: fails if the PR adds a vulnerable package |
| `ci.yml` → `npm audit signatures` | Verifies registry signatures and provenance |

Three tools, three moments:

| Tool | When | Question it answers |
|------|------|---------------------|
| Trivy (`sca` job) | Every push | "Does what we have **now** contain known CVEs?" |
| Dependency review | Every PR | "Does this PR **add** a vulnerable package?" |
| Dependabot | Weekly + on new advisories | "Is there a newer version? Open the PR for me" |

## A real finding: multer

The very first scan of this repo failed:

```
$ scripts/security/sca.sh
package-lock.json (npm)
Total: 1 (HIGH: 1, CRITICAL: 0)
│ multer  │ CVE-2026-113872 │ HIGH │ fixed │ 2.4.0 │ 2.5.0 │ Denial of Service via aborted request
```

We never installed `multer`. It comes with `@nestjs/platform-express`
(a **transitive** dependency):

```
$ npm ls multer
└─┬ @nestjs/platform-express@11.2.8
  └── multer@2.4.0
```

### The wrong fix: `npm audit fix`

`npm audit fix` resolved the alert by **downgrading**
`@nestjs/platform-express` to a version that does not use multer 2.x.
That pulled in `multer@1.4.5-lts.2`. Scanning again:

| | Before `npm audit fix` | After `npm audit fix` |
|-|-------------------------|-----------------------|
| HIGH vulnerabilities | 1 | **12** |

Lesson: automatic fixes are suggestions. Read the diff of
`package-lock.json` before committing it.

### The right fix: `overrides`

Even the latest NestJS (11.2.8 and 12.2.0) pins `multer` to exactly
`2.4.0`, so updating NestJS does not help. npm `overrides` forces a
transitive dependency to a given version:

```json
"overrides": {
  "multer": "^2.5.0"
}
```

```
$ npm install && npm ls multer
  └── multer@2.5.0
$ scripts/security/sca.sh   → exit 0
```

Remove the override once NestJS ships with the fixed version itself
(Dependabot will propose that update).

## Exercise: break it

```bash
npm install lodash@4.17.20
scripts/security/sca.sh
```

```
Total: 2 (HIGH: 2, CRITICAL: 0)
│ lodash │ CVE-2021-23337 │ HIGH │ fixed │ 4.17.20 │ 4.17.21 │ command injection via template
│        │ CVE-2026-4800  │      │       │         │ 4.18.0  │ Arbitrary code execution via untrusted input
exit 1
```

Undo it with `git checkout package.json package-lock.json && npm ci`.

## Gate policy

- **HIGH and CRITICAL with a fix available → the build fails.**
- No fix yet (`--ignore-unfixed`) → not blocking; Dependabot alerts
  track it until a patched version appears.
- MEDIUM and LOW → reported in the SARIF / Security tab, not blocking.
- Accepting a risk → add the ID to `.trivyignore` **with a reason and an
  expiry date**. An exception without an expiry date becomes permanent.

## Enable on GitHub

*Settings → Advanced Security*:

- **Dependency graph**: on (required by dependency review).
- **Dependabot alerts**: on.
- **Dependabot security updates**: on (PRs for CVEs, immediately).

`dependabot.yml` adds the *version updates*: regular PRs even without a
CVE, so you never fall years behind.

## Supply chain extras

- **`cooldown: 7 days`** in `dependabot.yml`: Dependabot waits a week
  before proposing a new release. Most malicious versions (account
  takeovers, typosquats) are found and removed within that window.
- **`npm audit signatures`**: checks that packages were signed by the
  registry and shows how many have provenance attestations.
- **npm install scripts**: npm 11.19+ no longer runs `postinstall`
  scripts unless allowed. You saw `npm warn install-scripts` when
  installing: that is the same protection.

## Renovate, the alternative

[Renovate](https://docs.renovatebot.com/) does the same job as
Dependabot with more options: automerge of patch versions, grouping
rules and custom "regex managers". With a regex manager it could also
bump the image digests in `scripts/security/images.sh`, which Dependabot
cannot read. For this repo Dependabot is enough and needs no app install.
