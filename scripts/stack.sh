#!/usr/bin/env bash
# Starts or stops the full stack in containers: PostgreSQL, Vault and the
# API image, with the API reading its secrets from Vault.
#
# Usage:
#   scripts/stack.sh up              build the image, start everything, wait until healthy
#   scripts/stack.sh up --no-build   use the existing dev-secops:local image as is
#                                    (CI: the image built and scanned once)
#   scripts/stack.sh down            stop everything (Vault dev data is lost)
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  up)
    build_flag="--build"
    if [[ "${2:-}" == "--no-build" ]]; then
      build_flag="--no-build"
    fi
    docker compose --profile app up -d --wait db vault
    # The role ID and secret ID only live in this shell's environment.
    eval "$(scripts/vault/setup.sh)"
    docker compose --profile app up -d "$build_flag" --wait api
    echo "API ready at http://localhost:3000/api (secrets loaded from Vault)"
    ;;
  down)
    docker compose --profile app down
    ;;
  *)
    echo "Usage: $0 up [--no-build] | down" >&2
    exit 2
    ;;
esac
