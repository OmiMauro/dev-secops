# Step 8 — Secrets in production (Vault, External Secrets)

## The problem

Step 2 kept secrets **out of git**. They still have to reach the running
app somehow. A `.env` file on a server, or secrets baked into CI
variables, has the same weaknesses:

- Everyone who can read the server or the CI settings can read them.
- Nobody knows who read them, or when.
- Rotating one means editing files by hand on every machine.

A secret manager stores secrets centrally, gives each app an identity,
lets it read **only its own** secrets, and logs every access.

## What was added

| File | Purpose |
|------|---------|
| `src/config/vault.ts` | Logs in to Vault with AppRole and loads secrets into `process.env` |
| `src/config/vault.spec.ts` | Unit tests (mocked `fetch`) |
| `src/main.ts` | Loads the secrets **before** importing `AppModule` |
| `docker-compose.yml` → `vault` | Vault dev server (`--profile app`) |
| `docker-compose.yml` → `api` | No more `env_file`: secrets only come from Vault |
| `scripts/vault/app-policy.hcl` | The API may read one path. Nothing else |
| `scripts/vault/setup.sh` | Stores secrets, writes the policy, creates the AppRole |
| `scripts/stack.sh` | `up` / `down` for db + Vault + API |

## How it works

```
scripts/stack.sh up
 │
 ├─ 1. start db and vault
 ├─ 2. scripts/vault/setup.sh  (as Vault admin)
 │     ├─ kv put secret/dev-secops/app DB_PASSWORD=… JWT_SECRET=…
 │     ├─ policy dev-secops-app: read secret/data/dev-secops/app
 │     └─ AppRole dev-secops-api → role_id + secret_id
 └─ 3. start api with VAULT_ADDR, VAULT_ROLE_ID, VAULT_SECRET_ID
           │
           │  POST /v1/auth/approle/login {role_id, secret_id}
           ├──────────────────────────────────────────────▶ Vault
           │◀────────────── token (15 min, policy dev-secops-app)
           │  GET /v1/secret/data/dev-secops/app
           ├──────────────────────────────────────────────▶ Vault
           │◀────────────── {DB_PASSWORD, JWT_SECRET}
           ▼
      process.env ← secrets, then `import('./app.module')`
```

Without `VAULT_ADDR` (for example `npm run start:dev`) the loader does
nothing and `.env` is used as before.

Why the dynamic import in `main.ts`? `ConfigModule.forRoot({ validate })`
runs as soon as `app.module.ts` is imported. A normal `import` at the top
of the file would validate the environment before Vault was asked, and
the app would refuse to start for a missing `JWT_SECRET`.

## Try it

```bash
scripts/stack.sh up
curl -s -H 'Content-Type: application/json' \
  -d '{"email":"me@test.com","password":"long-password-123"}' \
  localhost:3000/api/auth/register
```

It works, although the `api` container never received `DB_PASSWORD` or
`JWT_SECRET`:

```bash
docker compose --profile app exec api /nodejs/bin/node -e \
  "console.log(Object.keys(process.env).filter(k => /DB_|JWT|VAULT/.test(k)).join(' '))"
```

```
JWT_EXPIRES_IN VAULT_ADDR DB_PORT DB_HOST DB_NAME VAULT_SECRET_ID VAULT_ROLE_ID DB_USER
```

### Least privilege

With the API's own token (log in as the AppRole yourself, see
`setup.sh`):

```
GET   secret/data/dev-secops/app   → HTTP 200   its own secret
POST  secret/data/dev-secops/app   → HTTP 403   cannot change it
GET   secret/data/other-team/db    → HTTP 403   cannot read anything else
GET   sys/policies/acl             → HTTP 403   cannot manage Vault
```

If the API is compromised, the attacker gets the API's secrets and
nothing more.

### Exercise: rotate a secret

```bash
set -a; source .env; set +a
TOKEN=...   # log in and copy an accessToken
curl -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOKEN" localhost:3000/api/notes   # 200

docker compose exec -e VAULT_TOKEN=$VAULT_ROOT_TOKEN vault \
  vault kv patch -mount=secret dev-secops/app JWT_SECRET="$(openssl rand -base64 48)"
docker compose --profile app restart api

curl -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOKEN" localhost:3000/api/notes   # 401
```

One command in one place, and every token signed with the old secret
stops working. That is what you do when a secret leaks.

## The "secret zero" problem

Look at the variable list above again: `VAULT_SECRET_ID` is still in the
container's configuration (`docker inspect` shows it). The app deletes it
from its own `process.env` after logging in, but whoever starts the
container had to hand it over. Something always has to bootstrap the
first identity. It is called **secret zero**.

What this repo does to limit it:

- The secret ID expires after 24 h (`secret_id_ttl`), the token after 15 min.
- The secret ID is never written to a file; `stack.sh` keeps it in a
  shell variable.
- It only unlocks one read-only path.

What production does instead: **no secret ID at all**. The platform
already proves who the workload is, and Vault trusts that:

| Platform | Vault auth method | Identity proof |
|----------|-------------------|----------------|
| Kubernetes | `kubernetes` | The pod's service account token |
| AWS (ECS, EC2, Lambda) | `aws` | The IAM role, signed by AWS |
| GitHub Actions | `jwt` | The workflow's OIDC token (like Cosign in step 6) |

## Dev mode vs production

`server -dev` is deliberately insecure, so it is easy to use:

| Dev mode (here) | Production |
|-----------------|------------|
| Data in memory, lost on restart | Integrated storage (Raft), replicated |
| Already unsealed | Sealed on start; unsealed by a cloud KMS (auto-unseal) |
| Root token known and permanent | Root token revoked after setup; admins use SSO |
| Plain HTTP | TLS everywhere |
| No audit log | `vault audit enable file`: every read is logged |

## Going further: dynamic secrets

Here `DB_PASSWORD` is still a long-lived value copied into Vault. Vault's
**database secrets engine** can create a new PostgreSQL user for each app
instance, valid for one hour, and delete it afterwards. A leaked password
then expires on its own. The step 7 Terraform takes a similar approach
with RDS: `manage_master_user_password` lets AWS generate and rotate it.

## Kubernetes: External Secrets Operator

In Kubernetes the app usually does not talk to Vault at all. The
[External Secrets Operator](https://external-secrets.io) reads from Vault
(or AWS Secrets Manager, GCP...) and writes a regular Kubernetes `Secret`,
which the pod mounts as environment variables:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: dev-secops-app
spec:
  refreshInterval: 1h            # re-syncs after a rotation
  secretStoreRef:
    name: vault                  # a SecretStore with Vault's address and k8s auth
    kind: ClusterSecretStore
  target:
    name: dev-secops-app         # the Kubernetes Secret it creates
  dataFrom:
    - extract:
        key: dev-secops/app      # → DB_PASSWORD, JWT_SECRET
```

The app code stays the same as with `.env`, and the secret still has a
single source of truth. The Kubernetes course covers the operator in depth.
