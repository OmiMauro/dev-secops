#!/usr/bin/env bash
# Configures the local Vault dev server for the API:
#   1. stores the API secrets in the KV store
#   2. creates a read-only policy for them
#   3. creates an AppRole (a machine identity) bound to that policy
#   4. prints the role ID and a fresh secret ID as shell exports
#
# Usage: eval "$(scripts/vault/setup.sh)"     (scripts/stack.sh does this)
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# shellcheck disable=SC1091
set -a; source .env; set +a

# Runs the vault CLI inside the vault container, as root (admin) of the dev server.
vault() {
  docker compose exec -T -e VAULT_TOKEN="$VAULT_ROOT_TOKEN" vault vault "$@"
}

# Progress goes to stderr: stdout is reserved for the export lines.
log() { echo "==> $*" >&2; }

log "Storing the API secrets at secret/dev-secops/app"
# The values come from .env this time (migrating them into Vault). From
# now on Vault is the source of truth for the running API.
vault kv put -mount=secret dev-secops/app \
  DB_PASSWORD="$DB_PASSWORD" \
  JWT_SECRET="$JWT_SECRET" >/dev/null

log "Writing the read-only policy"
docker compose exec -T -e VAULT_TOKEN="$VAULT_ROOT_TOKEN" vault \
  vault policy write dev-secops-app - < scripts/vault/app-policy.hcl >/dev/null

log "Configuring the AppRole"
vault auth enable approle >/dev/null 2>&1 || true   # already enabled is fine
# token_ttl:     the API's Vault token lives 15 minutes; it only needs it at boot
# secret_id_ttl: a secret ID that leaks is useless after 24 hours
vault write auth/approle/role/dev-secops-api \
  token_policies=dev-secops-app \
  token_ttl=15m \
  token_max_ttl=1h \
  secret_id_ttl=24h >/dev/null

role_id="$(vault read -field=role_id auth/approle/role/dev-secops-api/role-id)"
secret_id="$(vault write -f -field=secret_id auth/approle/role/dev-secops-api/secret-id)"

echo "export VAULT_ROLE_ID=$role_id"
echo "export VAULT_SECRET_ID=$secret_id"
