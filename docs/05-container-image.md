# Step 5 — Container image (Dockerfile + Trivy)

## The problem

The image is what really runs in production. It contains our code, but
also an operating system, a Node runtime and `node_modules`. A clean
`package-lock.json` (step 3) says nothing about the OS packages of the
base image, and a careless Dockerfile can ship secrets or run as root.

## What was added

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage build → distroless, non-root, pinned by digest |
| `docs/examples/Dockerfile.insecure` | Counter-example with the usual mistakes |
| `.dockerignore` | Keeps `.env`, `.git` and friends out of the build context |
| `scripts/security/image.sh` | Dockerfile misconfig scan + image CVE/secret scan, with gate |
| `docker-compose.yml` → `api` | Runs the real image with runtime hardening (`--profile app`) |
| `src/migrations/`, `src/config/data-source.ts` | Versioned schema, needed now that production has `synchronize` off |
| `.github/dependabot.yml` → `docker` | PRs when a base image digest changes |
| `ci.yml` → `image` job | Builds, scans, uploads two SARIF reports |

## The numbers

Same app, two Dockerfiles, scanned with the same Trivy version:

| | `docs/examples/Dockerfile.insecure` | `Dockerfile` |
|-|------------------------------------|--------------|
| Base image | `node:24` (full Debian) | `distroless/nodejs24:nonroot` |
| Size | 2.1 GB | 359 MB |
| Runs as | root | UID 65532 |
| Shell, apt, curl | yes | no |
| CVEs, all severities | **4,863** (35 CRITICAL, 614 HIGH) | **31** (0 CRITICAL, 0 HIGH) |
| CVEs with a fix available | 433 | **0** |
| Gate (HIGH/CRITICAL fixable) | ❌ fails | ✅ passes |

Fewer packages means fewer CVEs: you cannot be vulnerable through a
package that is not there.

## How the Dockerfile is built

```
┌─ build (node:24-trixie-slim) ───┐
│ npm ci (with dev deps)          │
│ npm run build → dist/           │──┐
└─────────────────────────────────┘  │   only dist/ and prod
┌─ prod-deps (node:24-trixie-slim)┐  │   node_modules are copied
│ npm ci --omit=dev               │──┤
└─────────────────────────────────┘  ▼
                         ┌─ runtime (distroless:nonroot) ─┐
                         │ node + dist + node_modules     │
                         │ no shell, no npm, no root      │
                         └────────────────────────────────┘
```

Read the comments in the `Dockerfile`: every line explains its reason.

## Running it

```bash
scripts/stack.sh up            # since step 8 this also starts Vault
curl localhost:3000/api/health
scripts/stack.sh down
```

The `api` service adds **runtime** hardening on top of the image:
`read_only`, `cap_drop: [ALL]`, `no-new-privileges`. Checked from inside
the running container:

```
$ docker compose exec api sh
exec: "sh": executable file not found in $PATH      ← no shell to use

$ docker compose exec api /nodejs/bin/node -e "..."
uid 65532                                           ← not root
EROFS                                               ← writing to disk fails
```

## Scanning

```bash
scripts/security/image.sh                    # build dev-secops:local and scan it
scripts/security/image.sh my-image:tag       # scan an existing image
```

It runs three checks, each with the same HIGH/CRITICAL gate:

1. `trivy config Dockerfile`: misconfigurations.
2. `trivy image --scanners vuln`: CVEs in OS packages and `node_modules`.
3. `trivy image --scanners secret`: keys or tokens left in a layer.

The image is passed to Trivy as a tar (`docker save`) instead of mounting
`/var/run/docker.sock`. Whoever can talk to the Docker socket controls
the host, so a scanner should not need it.

## Exercise: break it

```bash
docker build -f docs/examples/Dockerfile.insecure -t dev-secops:insecure .
scripts/security/image.sh dev-secops:insecure
```

The gate fails on hundreds of fixable HIGH/CRITICAL CVEs. Scan the
insecure Dockerfile itself:

```bash
source scripts/security/lib.sh
run_trivy config docs/examples/Dockerfile.insecure
```

```
DS-0002 (HIGH): Specify at least 1 USER command in Dockerfile with non-root user as argument
DS-0026 (LOW):  Add HEALTHCHECK instruction in your Dockerfile
```

Then try removing `USER nonroot` from the real `Dockerfile` and run
`scripts/security/image.sh` again.

## Migrations instead of `synchronize`

Production now runs with `NODE_ENV=production`, so `synchronize` is off
(step 4) and TypeORM applies the migrations in `src/migrations/` at
startup (`migrationsRun`). After changing an entity:

```bash
set -a; source .env; set +a
npm run migration:generate -- src/migrations/DescribeTheChange
```

Review the generated SQL and commit it with the entity change.

## Base image choice

| Base | Size | Shell | Notes |
|------|------|-------|-------|
| `node:24` | ~1.6 GB | yes | Includes compilers and git. Fine for CI, not for production |
| `node:24-slim` | ~330 MB | yes | Good middle ground if you need a shell to debug |
| `node:24-alpine` | ~240 MB | yes | musl instead of glibc: native modules may behave differently |
| `distroless/nodejs24` | ~215 MB | no | Least to attack. Debug with `docker debug` or an ephemeral container |
